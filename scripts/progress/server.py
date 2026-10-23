#!/usr/bin/env python3
"""進捗一覧の web server（閲覧のみ）。

    python3 scripts/progress/server.py [--port 8765] [--ttl 60]

cwd の repo の epic / task / issue の木と、作業中・要対応・次の候補をブラウザに出す。
仕様: .spec/issues/176-progress-server.md
"""

import argparse
import datetime
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# 同じディレクトリのモジュール（スクリプトとして起動すると、このディレクトリが sys.path の先頭に入る）
import github
import local_git
import tree

HERE = Path(__file__).resolve().parent

JST = datetime.timezone(datetime.timedelta(hours=9))


def log(level, msg):
    print(f"[progress] {level}: {msg}", file=sys.stderr, flush=True)


def default_fetch():
    """実データを取る。戻り値は tree.build の結果。GitHub の失敗は FetchError、git の失敗は gitError に入れる。"""
    started = time.monotonic()
    repo = github.current_repo()
    issues = github.fetch_issues(repo)
    labels_file = HERE.parent / "setup-labels.sh"
    sections = tree.label_sections(labels_file.read_text()) if labels_file.exists() else {}
    try:
        branches, worktrees, git_error = local_git.read_branches(), local_git.read_worktrees(), None
    except github.FetchError as e:
        branches, worktrees, git_error = None, None, str(e)
        log("ERROR", f"git の読み取りに失敗（作業中は不明として出す）: {e}")
    result = tree.build(issues, repo, sections, branches, worktrees, git_error)
    log("INFO", f"取得 {repo}: issue {len(issues)} 件、ブランチ {len(branches or [])} 本、"
                f"{time.monotonic() - started:.1f} 秒")
    return result


class Cache:
    """取得結果を ttl 秒持つ。取得は lock で 1 本にまとめる（同時の要求は同じ結果を待つ）。"""

    def __init__(self, fetch, ttl, clock=time.time):
        self.fetch, self.ttl, self.clock = fetch, ttl, clock
        self.lock = threading.Lock()
        self.data, self.fetched_at, self.error, self.error_at = None, None, None, None

    def get(self, refresh=False):
        with self.lock:
            fresh = self.data is not None and self.clock() - self.fetched_at < self.ttl
            if refresh or not fresh:
                try:
                    self.data, self.fetched_at = self.fetch(), self.clock()
                    self.error = self.error_at = None
                except github.FetchError as e:
                    self.error, self.error_at = str(e), self.clock()
                    log("ERROR", f"GitHub からの取得に失敗: {e}")
            if self.data is None:
                return None
            return {**self.data, "fetchedAt": stamp(self.fetched_at), "ttl": self.ttl,
                    "error": self.error, "errorAt": stamp(self.error_at) if self.error_at else None}


def stamp(t):
    return datetime.datetime.fromtimestamp(t, JST).strftime("%Y-%m-%d %H:%M:%S JST")


def make_handler(cache, port):
    allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
    page = (HERE / "index.html").read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):  # アクセスログは出さない
            pass

        def send(self, code, body, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.headers.get("Host") not in allowed_hosts:
                return self.send(403, b"forbidden host\n", "text/plain; charset=utf-8")
            url = urlparse(self.path)
            if url.path == "/":
                return self.send(200, page, "text/html; charset=utf-8")
            if url.path == "/api/tree.json":
                data = cache.get(refresh="1" in parse_qs(url.query).get("refresh", []))
                if data is None:
                    body = json.dumps({"error": cache.error, "errorAt": stamp(cache.error_at)},
                                      ensure_ascii=False).encode()
                    return self.send(502, body, "application/json; charset=utf-8")
                return self.send(200, json.dumps(data, ensure_ascii=False).encode(),
                                 "application/json; charset=utf-8")
            return self.send(404, b"not found\n", "text/plain; charset=utf-8")

        def refuse(self):
            self.send(405, b"read-only\n", "text/plain; charset=utf-8")

        do_POST = do_PUT = do_DELETE = do_PATCH = refuse

    return Handler


def serve(port, ttl, fetch=default_fetch):
    cache = Cache(fetch, ttl)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(cache, port))
    return server, cache


def main():
    ap = argparse.ArgumentParser(description="進捗一覧の web server（閲覧のみ）")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--ttl", type=int, default=60, help="取得結果を持つ秒数")
    args = ap.parse_args()
    server, _ = serve(args.port, args.ttl)
    log("INFO", f"http://127.0.0.1:{args.port}/ （ttl {args.ttl} 秒。Ctrl-C で止める）")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
