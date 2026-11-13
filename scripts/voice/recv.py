#!/usr/bin/env python3
"""手元の PC から TCP で届く音（s16le / 16 kHz / mono）を、PulseAudio の null sink へ流す。

PulseAudio の module-simple-protocol-tcp を使わない理由: 再生 buffer が 0.5 秒しか無く、
溢れた音を黙って捨てる。ここでは pacat に渡し、溢れたら TCP 側で待たせる（捨てない）。
起動は scripts/voice/start.sh。使い方は .claude/rules/template/optional-features.md。
"""

import os
import shlex
import socket
import subprocess
import sys
import threading
import time

# 番号と sink 名の単一情報源。start.sh は --print-port・--print-sink で引く。
# devcontainer.json の portsAttributes と説明は tests が一致を検査する
PORT = 9257
SINK = "claude_mic"
BYTES_PER_SEC = 16000 * 2
# 届いた音をためてから流す長さ。短いと到着の揺れで途切れ、長いと話し終えてから待つ時間が延びる
LATENCY_MS = int(os.environ.get("CLAUDE_VOICE_LATENCY_MS", "1500"))
SINK_CMD = (
    "pacat --playback --raw --format=s16le --rate=16000 --channels=1 "
    f"--device={SINK} --latency-msec={LATENCY_MS} --client-name=claude-voice"
)
USAGE = "usage: recv.py [--print-port | --print-sink]"

# 同時に受けるのは 1 本だけ。2 本を混ぜると声が二重になり、認識が崩れる
_busy = threading.Lock()


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


def serve(conn, addr, sink_cmd):
    """1 本の接続を sink_cmd の標準入力へ写す。届いた量を 10 秒ごとに記録する。"""
    if not _busy.acquire(blocking=False):
        log(f"拒否 {addr}（別の送信側が接続中。送信側は 1 つだけ動かす）")
        conn.close()
        return
    proc, total = None, 0
    try:
        log(f"接続 {addr}")
        proc = subprocess.Popen(shlex.split(sink_cmd), stdin=subprocess.PIPE)
        start = last = report = time.monotonic()
        worst = 0.0
        while True:
            data = conn.recv(65536)
            if not data:
                break
            now = time.monotonic()
            worst = max(worst, now - last)
            last = now
            total += len(data)
            # 流し先が詰まればここで待つ（→ 送信側が TCP で待たされる）。捨てない
            proc.stdin.write(data)
            proc.stdin.flush()
            if now - report >= 10:
                log(f"届いた音 {total / BYTES_PER_SEC:.1f} 秒 / 経過 {now - start:.1f} 秒"
                    f"（ほぼ同じなら正常。届いた音が短ければ送信側の取りこぼし）、"
                    f"到着の間隔の最大 {worst * 1000:.0f} ms")
                report, worst = now, 0.0
    except (BrokenPipeError, ConnectionError) as e:
        log(f"切断 {type(e).__name__}")
    except OSError as e:
        log(f"流し先を起動できない: {e}")
    finally:
        conn.close()
        if proc is not None:
            try:
                proc.stdin.close()
            except BrokenPipeError:
                pass
            proc.wait()
        _busy.release()
        log(f"終了 {addr}（届いた音 {total / BYTES_PER_SEC:.1f} 秒）")


def listen(port=PORT):
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))  # 外には開けない。手元からは VS Code の port forward で届く
    srv.listen(4)
    return srv


def stop(srv):
    """accept_loop を終わらせる。close だけでは待っている accept が戻らないので、先に shutdown する。"""
    try:
        srv.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass  # 既に閉じている
    srv.close()


def accept_loop(srv, sink_cmd=SINK_CMD):
    while True:
        try:
            conn, addr = srv.accept()
        except OSError as e:
            log(f"待機を終了（{e}）")
            return
        threading.Thread(target=serve, args=(conn, addr, sink_cmd), daemon=True).start()


def main(argv):
    if argv[1:] == ["--print-port"]:
        print(PORT)
        return 0
    if argv[1:] == ["--print-sink"]:
        print(SINK)
        return 0
    if argv[1:]:
        print(USAGE, file=sys.stderr)
        return 2
    srv = listen()
    log(f"127.0.0.1:{PORT} で待機")
    accept_loop(srv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
