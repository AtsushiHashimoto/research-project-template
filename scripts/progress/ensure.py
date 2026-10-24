#!/usr/bin/env python3
"""進捗一覧のサーバーを確かめ、立っていなければ背景で立てて URL を出す（/progress の実体）。

    python3 scripts/progress/ensure.py [--port N] [--stop]

番号は repo ごとに 18000〜18999 の固定（--port > git config progress.port > repo 名の crc32）。
その番号が別のものに使われていれば立てずに終了コード 2。自動で別の番号を選ばない。
仕様: .spec/issues/212-progress-launcher.md
"""

import argparse
import datetime
import http.client
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
import zlib
from pathlib import Path

import progress_git
from progress_cmd import FetchError, run_raw

PORT_MIN, PORT_MAX = 18000, 18999          # .devcontainer/*/devcontainer.json の portsAttributes と同じ範囲（E6 が検査）
HERE = Path(__file__).resolve().parent
JST = datetime.timezone(datetime.timedelta(hours=9))
LOG_LIMIT = 1 << 20
HINT = (f"上書き: git config progress.port <{PORT_MIN}〜{PORT_MAX} の別の番号>（その clone に残る）"
        "か --port <番号>（その 1 回だけ）")


class Refused(Exception):
    """終了コード 2 で止める理由。"""


def repo_name(url):
    """origin の URL の最後の要素から .git を外したもの（scp 形式・https・末尾 / のどれでも同じ。§3-1）。"""
    return re.split(r"[/:]", url.strip().rstrip("/"))[-1].removesuffix(".git")


def formula(name):
    return PORT_MIN + zlib.crc32(name.lower().encode()) % (PORT_MAX - PORT_MIN + 1)


def parse_port(text, where):
    """整数の文字列だけを受け、範囲外は理由を出して止める（式の番号に黙って戻さない）。"""
    if not re.fullmatch(r"[0-9]+", text) or not PORT_MIN <= int(text) <= PORT_MAX:
        raise Refused(f"{where} の値 {text[:20]!r} は {PORT_MIN}〜{PORT_MAX} の整数ではない（範囲外は "
                      "requireLocalPort が掛からず、手元で黙ってずれうる）")
    return int(text)


def choose_port(cli, runner=run_raw):
    """§3-1: --port > git config progress.port > 式。"""
    if cli is not None:
        return parse_port(cli, "--port")
    code, out, _ = runner(["git", "config", "--get", "progress.port"])
    if code == 0:
        return parse_port(out.strip(), "git config progress.port")
    code, out, err = runner(["git", "remote", "get-url", "origin"])
    name = repo_name(out) if code == 0 else ""
    if not name:
        why = err.strip().splitlines()[0] if code != 0 and err.strip() else "repo 名が空"
        raise Refused(f"origin の URL から repo 名を決められない（{why}）。"
                      f"git config progress.port <{PORT_MIN}〜{PORT_MAX}> で番号を決める")
    return formula(name)


def fetch_identity(port, timeout=2):
    """('refused',) / ('timeout',) / ('error', 文字列) / ('http', status, body)。"""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request("GET", "/api/identity", headers={"Host": f"127.0.0.1:{port}"})
        r = conn.getresponse()
        return ("http", r.status, r.read(4096))
    except ConnectionRefusedError:
        return ("refused",)
    except (socket.timeout, TimeoutError):
        return ("timeout",)
    except (OSError, http.client.HTTPException) as e:
        return ("error", f"{type(e).__name__}: {e}")
    finally:
        conn.close()


def classify(result, common):
    """§4-1 の A・B・C。('A', None) / ('B', identity) / ('C', 理由)。"""
    if result[0] == "refused":
        return "A", None
    if result[0] == "timeout":
        return "C", "応答なし（別のもの、または高負荷）"
    if result[0] == "http":
        status, body = result[1], result[2]
        if status == 404 and body == b"not found\n":
            return "C", "/api/identity の無い古い進捗一覧の可能性。そのプロセスを手で止める"
        try:
            ident = json.loads(body) if status == 200 else None
        except ValueError:
            ident = None
        if isinstance(ident, dict) and ident.get("app") == "progress":
            other = ident.get("commonDir")
            if not isinstance(other, str):
                return "C", "進捗一覧だが commonDir が null（git common dir を求められなかった）"
            if os.path.realpath(other) == os.path.realpath(common):
                return "B", ident
            return "C", f"別の repo の進捗一覧（commonDir {other}）"
    return "C", "進捗一覧ではない"


def urls(port):
    return (f"http://127.0.0.1:{port}/\n"
            f"（コンテナの中の番号。VS Code 以外で転送するなら ssh -o ExitOnForwardFailure=yes "
            f"-L {port}:127.0.0.1:{port}）")


def start_server(port, cwd, log_path):
    """背景で server.py を立てる。ログに区切りの行を追記し、(子, 区切りの行) を返す。"""
    try:
        if os.path.getsize(log_path) > LOG_LIMIT:
            open(log_path, "w").close()
    except OSError:
        pass
    with open(log_path, "a", encoding="utf-8") as log:
        child = subprocess.Popen([sys.executable, str(HERE / "server.py"), "--port", str(port)], cwd=cwd,
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 start_new_session=True)
        mark = f"--- {datetime.datetime.now(JST):%Y-%m-%d %H:%M:%S} JST pid {child.pid} port {port}"
        log.write(mark + "\n")
    return child, mark


def log_tail(log_path, mark, n=20):
    """その回の区切りの行より後の末尾 n 行（他の呼び出しの出力を原因として見せない）。"""
    try:
        lines = Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    after = lines[lines.index(mark) + 1:] if mark in lines else []
    return after[-n:]


def wait_up(child, probe, clock=time.monotonic, sleep=time.sleep, wait=10, interval=0.2):
    """A の後半。(終了コード, 理由か identity)。"""
    deadline = clock() + wait
    while True:
        kind, info = probe()
        if kind == "B":
            return 0, info
        if child.poll() is not None:               # 子が先に終了した。もう一度判定する
            kind, info = probe()
            if kind == "B":
                return 0, info                     # 同時に呼ばれた別の呼び出しが立てた
            if kind == "C":
                return 2, info
            return 1, f"server.py が終了コード {child.returncode} で終わった"
        if clock() >= deadline:
            child.terminate()                      # 失敗と報告したのに後から立つことを防ぐ
            return 1, f"{wait} 秒で立たなかった（子 pid {child.pid} を止めた）"
        sleep(interval)


def ensure(port, common, cwd, log_path, probe=None, start=start_server, **wait_kw):
    """範囲の検査を通さない口（テストは空きの番号で呼ぶ）。(終了コード, 標準出力, 標準エラー)。"""
    probe = probe or (lambda: classify(fetch_identity(port), common))
    kind, info = probe()
    if kind == "B":
        return 0, urls(port), ""
    if kind == "C":
        return 2, "", f"127.0.0.1:{port} は別のものが使っている: {info}\n{HINT}"
    child, mark = start(port, cwd, log_path)
    code, info = wait_up(child, probe, **wait_kw)
    if code == 0:
        return 0, urls(port), ""
    if code == 2:
        return 2, "", f"127.0.0.1:{port} は別のものが使っている: {info}\n{HINT}"
    tail = "\n".join(log_tail(log_path, mark))
    return 1, "", f"立てられなかった: {info}\nログ: {log_path}\n{tail}\n{HINT}"


def read_cmdline(pid):
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace").split("\0")
    except OSError:
        return []


def is_our_server(argv, port):
    pairs = list(zip(argv, argv[1:]))
    return any(Path(a).name == "server.py" for a in argv) and ("--port", str(port)) in pairs


def stop(port, common, probe=None, cmdline=read_cmdline, kill=os.kill,
         clock=time.monotonic, sleep=time.sleep, wait=5, interval=0.1):
    """§3-2。(終了コード, 標準出力, 標準エラー)。"""
    probe = probe or (lambda: classify(fetch_identity(port), common))
    kind, info = probe()
    if kind == "A":
        return 0, f"127.0.0.1:{port} には立っていない", ""
    if kind == "C":
        return 2, "", f"127.0.0.1:{port} はこの repo の進捗一覧ではないので止めない: {info}"
    pid = info.get("pid")
    if not isinstance(pid, int) or not is_our_server(cmdline(pid), port):
        return 2, "", f"pid {pid} の cmdline が server.py --port {port} でないので止めない"
    kill(pid, signal.SIGTERM)
    deadline = clock() + wait
    while probe()[0] != "A":
        if clock() >= deadline:
            return 1, "", f"pid {pid} に SIGTERM を送ったが {wait} 秒で応答が無くならない"
        sleep(interval)
    return 0, f"止めた（pid {pid}、127.0.0.1:{port}）", ""


def main(argv=None):
    ap = argparse.ArgumentParser(description="進捗一覧のサーバーを確かめ、無ければ立てて URL を出す")
    ap.add_argument("--port", help=f"{PORT_MIN}〜{PORT_MAX}。その 1 回だけ（残すなら git config progress.port）")
    ap.add_argument("--stop", action="store_true", help="この repo のサーバーを止める")
    args = ap.parse_args(argv)
    try:
        port = choose_port(args.port)
        common = progress_git.common_dir()
        if args.stop:
            code, out, err = stop(port, common)
        else:
            cwd = progress_git.main_worktree() or progress_git.run(["git", "rev-parse", "--show-toplevel"]).strip()
            code, out, err = ensure(port, common, cwd, os.path.join(common, "progress-server.log"))
    except Refused as e:
        code, out, err = 2, "", str(e)
    except FetchError as e:
        code, out, err = 2, "", f"git を読めない: {e}"
    if out:
        print(out)
    if err:
        print(f"[progress] {err}", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
