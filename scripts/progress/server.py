#!/usr/bin/env python3
"""進捗一覧の web server（閲覧のみ。例外は子が 0 件の epic・task の close だけ）。

    python3 scripts/progress/server.py [--port 8765] [--ttl 60]

cwd の repo の epic / task / issue の木と、要対応・作業中・次の候補をブラウザに出す。
仕様: .spec/issues/176-progress-server.md、表示の木と query は .spec/issues/194-progress-collapse.md §4-1、
作業中の判定・カード・close の経路は .spec/issues/201-progress-cards.md
"""

import argparse
import datetime
import json
import re
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# 同じディレクトリのモジュール（スクリプトとして起動すると、このディレクトリが sys.path の先頭に入る）
import progress_close
import progress_gh
import progress_git
import progress_tree
import progress_view
from progress_cmd import FetchError, run_raw

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


def read_git():
    """(refs, worktrees, 基準, 基準に無い refname の集合, 失敗の理由)。失敗したら前の 4 つは None。"""
    try:
        refs, worktrees, base = progress_git.read_refs(), progress_git.read_worktrees(), progress_git.read_base()
        unmerged = progress_git.read_unmerged(base) if base else set()
        return refs, worktrees, base, unmerged, None
    except FetchError as e:
        log("ERROR", f"git の読み取りに失敗（作業中・次の候補は不明として出す）: {e}")
        return None, None, None, None, str(e)


def default_fetch():
    """実データを取る。issue の失敗は FetchError。git・PR・ラベル定義の失敗は木に添えて返す。"""
    started, now = time.monotonic(), time.time()
    repo = progress_gh.current_repo()
    with ThreadPoolExecutor(2) as pool:          # issue と PR を並行に取る（with を出るとき両方の完了を待つ）
        issues_f = pool.submit(progress_gh.fetch_issues, repo)
        pulls_f = pool.submit(progress_gh.fetch_pulls, repo)
    issues = issues_f.result()
    try:
        pulls, pulls_error = pulls_f.result(), None
    except FetchError as e:
        pulls, pulls_error = None, str(e)
        log("ERROR", f"PR の取得に失敗（作業中・次の候補は不明として出す）: {e}")
    sections, labels_error = read_label_sections()
    if labels_error:
        log("WARN", f"ラベルの検査をしない: {labels_error}")
    refs, worktrees, base, unmerged, git_error = read_git()
    if git_error is None and base is None:
        log("WARN", "基準のブランチ（origin/main・main）が無い（作業中・次の候補は不明として出す）")
    result = progress_tree.build(issues, repo, sections or {}, refs, worktrees, pulls, base, now,
                                 unmerged, git_error, pulls_error)
    result["labelsError"] = labels_error
    count = "不明" if refs is None else len(refs)
    prs = "不明" if pulls is None else len(pulls)
    log("INFO", f"取得 {repo}: issue {len(issues)} 件、PR {prs} 件、ref {count} 本、{time.monotonic() - started:.1f} 秒")
    return result


class Cache:
    """取得結果を ttl 秒持つ。失敗した後も ttl 秒は取り直さない。
    取得は lock で 1 本にまとめ、待っていた要求は自分が来た後に終わった取得の結果を使う。
    close の後は invalidate() で世代を進める。取得中に世代が変わったら、その結果を「新しい」とみなさない（201 §6）。"""

    def __init__(self, fetch, ttl, clock=time.time):
        self.fetch, self.ttl, self.clock = fetch, ttl, clock
        self.lock = threading.Lock()
        self.data, self.fetched_at, self.error, self.error_at = None, None, None, None
        self.generation, self.dirty, self.gen_lock = 0, False, threading.Lock()

    def invalidate(self):
        with self.gen_lock:
            self.generation += 1
            self.dirty = True

    def get(self, refresh=False):
        """(表示する JSON か None, 失敗の理由, 失敗の時刻) を返す（lock の中で読んだ値の組）。"""
        arrived = self.clock()
        with self.lock:
            last = max(self.fetched_at or 0, self.error_at or 0)
            if refresh:
                need = self.dirty or last < arrived
            else:
                need = last == 0 or self.dirty or self.clock() - last >= self.ttl
            if need:
                self.attempt()
            error_at = stamp(self.error_at) if self.error_at else None
            if self.data is None:
                return None, self.error, error_at
            return ({**self.data, "fetchedAt": stamp(self.fetched_at), "ttl": self.ttl,
                     "error": self.error, "errorAt": error_at}, self.error, error_at)

    def attempt(self):
        gen, self.dirty = self.generation, False
        try:
            self.data, self.fetched_at = self.fetch(), self.clock()
            self.error = self.error_at = None
        except Exception as e:  # noqa: BLE001  どんな失敗でも前回の木を残して帯に出す
            self.error, self.error_at = (str(e) if isinstance(e, FetchError) else f"{type(e).__name__}: {e}"), self.clock()
            if not isinstance(e, FetchError):
                log("ERROR", traceback.format_exc().rstrip())
            log("ERROR" if self.data is None else "WARN",
                f"GitHub からの取得に失敗{'' if self.data is None else '（前回の木を出す）'}: {self.error}")
        if self.generation != gen:      # 取得中に close があった。次の要求で取り直す
            self.dirty = True


def stamp(t):
    return datetime.datetime.fromtimestamp(t, JST).strftime("%Y-%m-%d %H:%M:%S JST")


Q_MAX = 200
CLOSE_PATH = "/api/close"
# 201 §6: 他のサイトの iframe に入れさせない（中の fetch は Origin・Host とも 127.0.0.1 になり、close の検査を通るため）
FRAME_DENY = (("X-Frame-Options", "DENY"), ("Content-Security-Policy", "frame-ancestors 'none'"))


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


def loopback(host):
    """DNS rebinding 対策なのでホスト名だけを見る。ポートは見ない（ポート転送で手元の番号が変わる）。"""
    return re.sub(r":\d+$", "", host or "") in LOOPBACK_HOSTS


def make_handler(cache, runner):
    page = (HERE / "index.html").read_bytes()
    script = (HERE / "page.js").read_bytes()

    class Handler(BaseHTTPRequestHandler):
        timeout = 10   # 宣言より短い本文で rfile.read が止まり続けないように
        def log_message(self, *args):  # アクセスログは出さない
            pass

        def end_headers(self):
            """標準の send_error（400・414・501）も通るここで付ける（201 §6。全応答を iframe に入れさせない）。"""
            for k, v in FRAME_DENY:
                self.send_header(k, v)
            super().end_headers()

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
            if not loopback(self.headers.get("Host")):
                return self.forbidden_host()
            url = urlparse(self.path)
            if url.path == "/":
                return self.send(200, page, "text/html; charset=utf-8")
            if url.path == CLOSE_PATH:
                return self.refuse()
            if url.path == "/page.js":
                return self.send(200, script, "text/javascript; charset=utf-8")
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

        def forbidden_host(self):
            port = self.server.server_address[1]
            self.send(403, f"forbidden host（http://127.0.0.1:{port}/ で開く）\n".encode(), "text/plain; charset=utf-8")

        def do_POST(self):
            """201 §6。順 1・2 だけをここで見て、残りは progress_close に任せる。"""
            if not loopback(self.headers.get("Host")):
                return self.forbidden_host()
            if urlparse(self.path).path != CLOSE_PATH:
                return self.refuse()
            bad = progress_close.check_request(self.headers, self.headers.get("Host"))
            if bad:
                return self.send_json(bad[0], {"error": bad[1]})
            number = progress_close.parse_body(self.rfile.read(int(self.headers["Content-Length"])))
            if isinstance(number, tuple):
                return self.send_json(number[0], {"error": number[1]})
            repo = (cache.data or {}).get("repo")
            if not repo:
                return self.send_json(409, {"error": "一覧をまだ取得していない"})
            code, body, attempted = progress_close.perform(number, repo, runner)
            if attempted:                    # 順 8: close を試みたら（失敗しても）無効化する
                cache.invalidate()
            log("INFO", f"close #{number}: {code} {body}")
            return self.send_json(code, body)

        def refuse(self):
            allow = "POST" if urlparse(self.path).path == CLOSE_PATH else "GET"
            self.send(405, b"read-only\n", "text/plain; charset=utf-8", (("Allow", allow),))

        do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = do_TRACE = do_CONNECT = refuse

    return Handler


def serve(port, ttl, fetch=default_fetch, runner=run_raw):
    cache = Cache(fetch, ttl)
    return ThreadingHTTPServer(("127.0.0.1", port), make_handler(cache, runner)), cache


def main():
    ap = argparse.ArgumentParser(description="進捗一覧の web server（閲覧のみ。子が 0 件の epic・task の close だけを受ける）")
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
