"""進捗一覧 web server（scripts/progress/server.py）の回帰テスト。

差し込みの取得関数だけで動く（ネットワーク・git 不要）。対応する判定は .spec/issues/176-progress-server.md §7 の V5〜V7。
"""

import http.client
import json
import re
import sys
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import (
    PROGRESS,
    REPO,
    SECTIONS,
    built,
    cmd,
    server,
    tree,
)


class FakeClock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class CacheRules(unittest.TestCase):
    def test_ttl_and_backoff(self):
        clock, calls = FakeClock(), []

        def fetch():
            calls.append(clock.t)
            if len(calls) == 2:
                raise cmd.FetchError("落ちた")
            return {"n": len(calls)}
        c = server.Cache(fetch, 60, clock)
        self.assertEqual(c.get()[0]["n"], 1)
        clock.t += 30
        c.get()
        self.assertEqual(len(calls), 1)                             # ttl 内は取り直さない
        clock.t += 31
        data, error, _ = c.get()
        self.assertEqual((data["n"], error), (1, "落ちた"))         # 失敗しても前回の木
        clock.t += 30
        c.get()
        self.assertEqual(len(calls), 2)                             # 失敗の後も ttl 内は取り直さない
        clock.t += 31
        self.assertEqual(c.get()[0]["n"], 3)

    def test_unexpected_exception_is_reported(self):
        def fetch():
            raise KeyError("issues")
        data, error, error_at = server.Cache(fetch, 60).get()
        self.assertIsNone(data)
        self.assertEqual(error, "KeyError: 'issues'")
        self.assertIsNotNone(error_at)

    def test_concurrent_requests_share_one_fetch(self):
        calls, gate = [], threading.Event()

        def fetch():
            calls.append(1)
            gate.wait(1)
            return {}
        c = server.Cache(fetch, 60)
        threads = [threading.Thread(target=c.get, kwargs={"refresh": True}) for _ in range(4)]
        for t in threads:
            t.start()
        time.sleep(0.05)
        gate.set()
        for t in threads:
            t.join()
        self.assertEqual(len(calls), 1)


class Server(unittest.TestCase):
    def start(self, fetch):
        srv, _ = server.serve(0, 60, fetch)
        threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        return srv.server_address[1]

    def req(self, port, method="GET", path="/api/tree.json", host=None, headers=None):
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        c.request(method, path, headers={"Host": host or f"127.0.0.1:{port}", **(headers or {})})
        r = c.getresponse()
        return r.status, r.read()

    def test_v5_read_only_and_host(self):
        port = self.start(built)
        for m in ("POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"):
            self.assertEqual(self.req(port, m)[0], 405, m)
        self.assertEqual(self.req(port, host="evil.example:80")[0], 403)
        self.assertEqual(self.req(port, path="/", host=f"localhost:{port}")[0], 200)
        # ポート転送で手元のポート番号が変わっても開ける。ホスト名が違えば同じポートでも拒む
        self.assertEqual(self.req(port, path="/", host=f"127.0.0.1:{port + 1}")[0], 200)
        self.assertEqual(self.req(port, path="/", host="localhost")[0], 200)
        self.assertEqual(self.req(port, path="/", host=f"evil.example:{port}")[0], 403)
        self.assertEqual(self.req(port, path="/", host=f"127.0.0.1.evil.example:{port}")[0], 403)

    def test_refresh_needs_page_header(self):
        calls = []
        port = self.start(lambda: calls.append(1) or built())
        self.req(port)
        self.req(port, path="/api/tree.json?refresh=1")             # 他のサイトの <img> 等
        self.assertEqual(len(calls), 1)
        self.req(port, path="/api/tree.json?refresh=1", headers={"X-Progress-Refresh": "1"})
        self.assertEqual(len(calls), 2)

    def test_v6_escape(self):
        port = self.start(built)
        status, body = self.req(port)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["nodes"]["70"]["title"], "<script>alert(1)</script>")
        page = (PROGRESS / "index.html").read_text(encoding="utf-8")
        for sink in ("innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval("):
            self.assertNotIn(sink, page)

    def test_v7_stale_and_502(self):
        calls = []

        def flaky():
            calls.append(1)
            if len(calls) > 1:
                raise cmd.FetchError("2 ページ目で失敗")
            return built()
        port = self.start(flaky)
        self.assertEqual(self.req(port)[0], 200)
        status, body = self.req(port, path="/api/tree.json?refresh=1", headers={"X-Progress-Refresh": "1"})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["error"], "2 ページ目で失敗")

        def broken():
            raise cmd.FetchError("gh が無い")
        status, body = self.req(self.start(broken))
        self.assertEqual(status, 502)
        self.assertEqual(json.loads(body)["error"], "gh が無い")

    def test_view_query(self):
        """194 §4-1: 受け付けない query は 400。絞り込みは取り直しと同時に渡せる。"""
        port = self.start(built)
        for bad in ("closed=2", "closed=true", "q=" + "x" * 201, "label=a&label=b", "q=a&q=b", "closed=1&closed=1"):
            status, body = self.req(port, path="/api/tree.json?" + bad)
            self.assertEqual(status, 400, bad)
            self.assertIn("error", json.loads(body))
        self.assertEqual(self.req(port, path="/api/tree.json?q=" + "x" * 200)[0], 200)
        status, body = self.req(port, path="/api/tree.json?refresh=1&q=%23770", headers={"X-Progress-Refresh": "1"})
        v = json.loads(body)["view"]
        self.assertEqual(status, 200)
        self.assertEqual(v["query"], {"closed": False, "label": "", "q": "#770"})
        self.assertEqual([it["number"] for it in v["epics"]], [1])
        v = json.loads(self.req(port, path="/api/tree.json?closed=1&label=blocked")[1])["view"]
        self.assertEqual(v["query"], {"closed": True, "label": "blocked", "q": ""})

    def test_empty_repo(self):
        self.assertEqual(self.req(self.start(lambda: tree.build([], REPO, SECTIONS, [], [])))[0], 200)

    def test_no_write_paths_in_code(self):
        for f in PROGRESS.glob("*.py"):
            text = f.read_text(encoding="utf-8")
            self.assertNotRegex(text, r"\bmutation\b", f.name)
            for call in re.findall(r'\["(gh|git)", "([^"]+)"', text):
                self.assertIn(call, {("gh", "repo"), ("gh", "api"), ("git", "for-each-ref"), ("git", "worktree")}, f.name)
            self.assertNotRegex(text, r'"(-X|--method|edit|close|comment|push|commit)"', f.name)


if __name__ == "__main__":
    unittest.main()
