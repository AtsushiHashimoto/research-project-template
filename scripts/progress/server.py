#!/usr/bin/env python3
"""進捗一覧の web server（閲覧のみ）。

    python3 scripts/progress/server.py [--port 8765] [--ttl 60]

cwd の repo の epic / task / issue の木と、要対応・作業中・次の候補をブラウザに出す。
仕様: .spec/issues/176-progress-server.md、表示の木と query は .spec/issues/194-progress-collapse.md §4-1
"""

import argparse
import datetime
import json
import re
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# 同じディレクトリのモジュール（スクリプトとして起動すると、このディレクトリが sys.path の先頭に入る）
import progress_gh
import progress_git
import progress_tree
import progress_view
from progress_cmd import FetchError

LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "[::1]"}

HERE = Path(__file__).resolve().parent
JST = datetime.timezone(datetime.timedelta(hours=9))


def log(level, msg):
    print(f"[progress] {level}: {msg}", file=sys.stderr, flush=True)


def read_label_sections():
    """表示する repo（cwd）の setup-labels.sh を読む。無ければこのスクリプトの隣。読めなければ (None, 理由)。"""
    for path in (Path.cwd() / "scripts" / "setup-labels.sh", HERE.parent / "setup-labels.sh"):
        if path.is_file():
            sections = progress_tree.label_sections(path.read_text(encoding="utf-8", errors="replace"))
            if "種類" in sections:
                return sections, None
            return None, f"{path} に「# --- 種類ラベル」の見出しが無い"
    return None, "scripts/setup-labels.sh が無い"


def default_fetch():
    """実データを取る。GitHub の失敗は FetchError。git・ラベル定義の失敗は木に添えて返す。"""
    started = time.monotonic()
    repo = progress_gh.current_repo()
    issues = progress_gh.fetch_issues(repo)
    sections, labels_error = read_label_sections()
    if labels_error:
        log("WARN", f"ラベルの検査をしない: {labels_error}")
    try:
        branches, worktrees, git_error = progress_git.read_branches(), progress_git.read_worktrees(), None
    except FetchError as e:
        branches, worktrees, git_error = None, None, str(e)
        log("ERROR", f"git の読み取りに失敗（作業中・次の候補は不明として出す）: {e}")
    result = progress_tree.build(issues, repo, sections or {}, branches, worktrees, git_error)
    result["labelsError"] = labels_error
    count = "不明" if branches is None else len(branches)
    log("INFO", f"取得 {repo}: issue {len(issues)} 件、ブランチ {count} 本、{time.monotonic() - started:.1f} 秒")
    return result


class Cache:
    """取得結果を ttl 秒持つ。失敗した後も ttl 秒は取り直さない。
    取得は lock で 1 本にまとめ、待っていた要求は自分が来た後に終わった取得の結果を使う。"""

    def __init__(self, fetch, ttl, clock=time.time):
        self.fetch, self.ttl, self.clock = fetch, ttl, clock
        self.lock = threading.Lock()
        self.data, self.fetched_at, self.error, self.error_at = None, None, None, None

    def get(self, refresh=False):
        """(表示する JSON か None, 失敗の理由, 失敗の時刻) を返す（lock の中で読んだ値の組）。"""
        arrived = self.clock()
        with self.lock:
            last = max(self.fetched_at or 0, self.error_at or 0)
            if refresh:
                need = last < arrived
            else:
                need = last == 0 or self.clock() - last >= self.ttl
            if need:
                self.attempt()
            error_at = stamp(self.error_at) if self.error_at else None
            if self.data is None:
                return None, self.error, error_at
            return ({**self.data, "fetchedAt": stamp(self.fetched_at), "ttl": self.ttl,
                     "error": self.error, "errorAt": error_at}, self.error, error_at)

    def attempt(self):
        try:
            self.data, self.fetched_at = self.fetch(), self.clock()
            self.error = self.error_at = None
        except Exception as e:  # noqa: BLE001  どんな失敗でも前回の木を残して帯に出す
            self.error, self.error_at = (str(e) if isinstance(e, FetchError) else f"{type(e).__name__}: {e}"), self.clock()
            if not isinstance(e, FetchError):
                log("ERROR", traceback.format_exc().rstrip())
            log("ERROR" if self.data is None else "WARN",
                f"GitHub からの取得に失敗{'' if self.data is None else '（前回の木を出す）'}: {self.error}")


def stamp(t):
    return datetime.datetime.fromtimestamp(t, JST).strftime("%Y-%m-%d %H:%M:%S JST")


Q_MAX = 200


def view_args(query):
    """query → (closed, label, q) か、受け付けない理由の文字列（§4-1。黙って既定に倒さない）。"""
    qs = parse_qs(query, keep_blank_values=True)
    for name in ("closed", "label", "q"):
        if len(qs.get(name, [])) > 1:
            return f"{name} が 2 回以上ある"
    closed = qs.get("closed", ["0"])[0]
    if closed not in ("0", "1"):
        return f"closed は 0 か 1: {closed[:20]!r}"
    q = qs.get("q", [""])[0]
    if len(q) > Q_MAX:
        return f"q は {Q_MAX} 文字まで（{len(q)} 文字）"
    return closed == "1", qs.get("label", [""])[0], q


def make_handler(cache):
    page = (HERE / "index.html").read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):  # アクセスログは出さない
            pass

        def send(self, code, body, ctype, extra=()):
            self.send_response(code)
            for k, v in (("Content-Type", ctype), ("Content-Length", str(len(body))),
                         ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"), *extra):
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def send_json(self, code, obj):
            self.send(code, json.dumps(obj, ensure_ascii=False).encode(), "application/json; charset=utf-8")

        def do_GET(self):
            port = self.server.server_address[1]
            # DNS rebinding 対策なのでホスト名だけを見る。ポートは見ない（ポート転送で手元の番号が変わる）
            if re.sub(r":\d+$", "", self.headers.get("Host") or "") not in LOOPBACK_HOSTS:
                return self.send(403, f"forbidden host（http://127.0.0.1:{port}/ で開く）\n".encode(),
                                 "text/plain; charset=utf-8")
            url = urlparse(self.path)
            if url.path == "/":
                return self.send(200, page, "text/html; charset=utf-8")
            if url.path == "/api/tree.json":
                args = view_args(url.query)
                if isinstance(args, str):
                    return self.send_json(400, {"error": args})
                # 取り直しはページの JS からだけ受ける（他のサイトの <img> 等から GitHub の利用枠を使わせない）
                refresh = ("1" in parse_qs(url.query).get("refresh", [])
                           and self.headers.get("X-Progress-Refresh") == "1")
                data, error, error_at = cache.get(refresh=refresh)
                if data is None:
                    return self.send_json(502, {"error": error, "errorAt": error_at})
                return self.send_json(200, {**data, "view": progress_view.view(data, *args)})
            return self.send(404, b"not found\n", "text/plain; charset=utf-8")

        def refuse(self):
            self.send(405, b"read-only\n", "text/plain; charset=utf-8", (("Allow", "GET"),))

        do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = do_TRACE = do_CONNECT = refuse

    return Handler


def serve(port, ttl, fetch=default_fetch):
    cache = Cache(fetch, ttl)
    return ThreadingHTTPServer(("127.0.0.1", port), make_handler(cache)), cache


def main():
    ap = argparse.ArgumentParser(description="進捗一覧の web server（閲覧のみ）")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--ttl", type=int, default=60, help="取得結果を持つ秒数")
    args = ap.parse_args()
    if not 0 <= args.port <= 65535:
        ap.error(f"--port は 0〜65535: {args.port}")
    try:
        server, _ = serve(args.port, args.ttl)
    except OSError as e:
        sys.exit(f"[progress] ERROR: 127.0.0.1:{args.port} で待ち受けられない（{e.strerror}）。--port で別の番号を指定する")
    log("INFO", f"http://127.0.0.1:{server.server_address[1]}/ （ttl {args.ttl} 秒。Ctrl-C で止める）")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
