"""子が 0 件の epic・task の close の経路（progress_close.py・server.py の POST）の回帰テスト。

差し込みの runner だけで動く（実際の issue を close しない。ネットワーク・git 不要）。
対応する判定は .spec/issues/201-progress-cards.md §9 の W5（§6 の順 1〜8）。
"""

import http.client
import json
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import built, cmd, pclose, server

CLOSE_ARGV = ["gh", "issue", "close", "30", "--repo", "o/r", "--reason", "not planned"]


def state(st="OPEN", labels=("epic",), subs=0):
    return json.dumps({"data": {"repository": {"issue": {
        "state": st, "labels": {"totalCount": len(labels), "nodes": [{"name": x} for x in labels]},
        "subIssues": {"totalCount": subs}}}}})


class Runner:
    """argv を記録し、state の読み取りと close に決めた応答を返す。"""

    def __init__(self, read=None, close=(0, "", "")):
        self.read, self.close, self.calls = read or (0, state(), ""), close, []

    def __call__(self, argv):
        self.calls.append(argv)
        out = self.close if argv[:3] == ["gh", "issue", "close"] else self.read
        if isinstance(out, Exception):     # run_raw は実行できない・timeout を FetchError で投げる
            raise out
        return out


TIMEOUT = cmd.FetchError("gh を実行できない: Command '...' timed out after 60 seconds")


OK = {"Origin": "http://127.0.0.1:8765", "Content-Type": "application/json; charset=utf-8",
      "X-Progress-Close": "1", "Content-Length": "15"}


class Checks(unittest.TestCase):
    def test_headers(self):
        host = "127.0.0.1:8765"
        self.assertIsNone(pclose.check_request(OK, host))                        # charset 付きは通る
        cases = [({"Origin": None}, 403), ({"Origin": "null"}, 403), ({"Origin": "http://127.0.0.1:8766"}, 403),
                 ({"Origin": "http://evil.example"}, 403), ({"Content-Type": "text/plain"}, 403),
                 ({"X-Progress-Close": None}, 403), ({"Content-Length": None}, 411),
                 ({"Transfer-Encoding": "chunked"}, 411), ({"Content-Length": "1025"}, 413),
                 ({"Content-Length": "0"}, 400), ({"Content-Length": "x"}, 400)]
        for change, code in cases:
            h = {k: v for k, v in {**OK, **change}.items() if v is not None}
            self.assertEqual(pclose.check_request(h, host)[0], code, change)

    def test_body(self):
        self.assertEqual(pclose.parse_body(b'{"number": 30}'), 30)
        for raw in (b'{"number": true}', b'{"number": -1}', b'{"number": "30"}', b"[30]", b"x", b"\xff"):
            self.assertEqual(pclose.parse_body(raw)[0], 400, raw)

    def test_perform(self):
        r = Runner()
        self.assertEqual(pclose.perform(30, "o/r", r), (200, {"closed": 30}, True))
        self.assertEqual(r.calls[-1], CLOSE_ARGV)
        self.assertIn("-F", r.calls[0])                                      # 番号は Int で渡す
        not_found = (1, json.dumps({"data": {"repository": {"issue": None}},
                                    "errors": [{"type": "NOT_FOUND", "message": "x"}]}), "gh: x")
        for read, code in [(not_found, 409), ((1, "", "network down"), 502), ((0, state("CLOSED"), ""), 409),
                           ((0, state(labels=("feature",)), ""), 409), ((0, state(subs=1), ""), 409)]:
            r = Runner(read=read)
            self.assertEqual(pclose.perform(30, "o/r", r)[0], code, read)
            self.assertNotIn(CLOSE_ARGV, r.calls)                            # 確かめられなければ close しない
        self.assertEqual(pclose.perform(30, "o/r", Runner(close=(1, "", "HTTP 403\n")))[::2], (502, True))
        self.assertFalse(pclose.perform(30, "o/r", Runner(read=(0, state(subs=1), "")))[2])   # 試みていない

    def test_perform_close_cannot_run(self):
        """#216: gh issue close が timeout・OSError でも例外を漏らさず 502、試みた扱い（順 8 で無効化）。"""
        code, body, attempted = pclose.perform(30, "o/r", Runner(close=TIMEOUT))
        self.assertEqual((code, attempted), (502, True))
        self.assertIn("timed out", body["error"])
        self.assertIn("不明", body["error"])                                 # close が通ったかは分からない
        code, _, attempted = pclose.perform(30, "o/r", Runner(read=TIMEOUT))
        self.assertEqual((code, attempted), (502, False))                    # 確認の失敗は試みていない


class Endpoint(unittest.TestCase):
    def start(self, runner):
        srv, cache = server.serve(0, 60, built, runner)
        threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        return srv.server_address[1], cache

    def post(self, port, path="/api/close", body=b'{"number": 30}', host=None, method="POST", **over):
        host = host or f"127.0.0.1:{port}"
        h = {"Host": host, "Origin": f"http://{host}", "Content-Type": "application/json",
             "X-Progress-Close": "1", "Content-Length": str(len(body)), **over}
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        c.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
        for k, v in h.items():
            c.putheader(k, v)
        c.endheaders(body)
        res = c.getresponse()
        return res.status, dict(res.getheaders()), res.read()

    def test_post_close(self):
        r = Runner()
        port, cache = self.start(r)
        self.assertEqual(self.post(port)[0], 409)                            # 一覧をまだ取得していない
        cache.get()
        gen = cache.generation
        status, _, body = self.post(port)
        self.assertEqual((status, json.loads(body)), (200, {"closed": 30}))
        self.assertEqual(r.calls[-1], CLOSE_ARGV)
        self.assertEqual(cache.generation, gen + 1)
        self.assertEqual(self.post(port, host="evil.example")[0], 403)
        self.assertEqual(self.post(port, Origin="null")[0], 403)
        status, headers, _ = self.post(port, path="/api/tree.json")
        self.assertEqual((status, headers.get("Allow")), (405, "GET"))
        for m in ("PUT", "GET"):
            status, headers, _ = self.post(port, method=m)
            self.assertEqual((status, headers.get("Allow")), (405, "POST"), m)
        lower = {"origin": f"http://127.0.0.1:{port}", "content-type": "application/json", "x-progress-close": "1"}
        status, _, _ = self.post(port, **lower)                  # ヘッダ名の大小は区別しない
        status, headers, _ = self.post(port, method="OPTIONS")
        self.assertEqual(status, 405)
        self.assertFalse([k for k in headers if k.lower().startswith("access-control")])
        self.assertEqual(sum(c == CLOSE_ARGV for c in r.calls), 2)

    def test_close_cannot_run_returns_502_and_invalidates(self):
        """#216: close の runner が FetchError でも応答が返り、キャッシュを無効にする。"""
        port, cache = self.start(Runner(close=TIMEOUT))
        cache.get()
        gen = cache.generation
        status, _, body = self.post(port)
        self.assertEqual(status, 502)
        self.assertIn("timed out", json.loads(body)["error"])
        self.assertEqual(cache.generation, gen + 1)

    def test_frame_deny_headers(self):
        """#216: どの応答も iframe に入れさせない（clickjacking で close を押させない）。"""
        port, cache = self.start(Runner())
        responses = [self.post(port, method="GET", path=p, body=b"") for p in ("/", "/page.js", "/api/tree.json", "/x")]
        responses += [self.post(port), self.post(port, Origin="null"), self.post(port, method="PUT")]
        for status, headers, _ in responses:
            self.assertEqual(headers.get("X-Frame-Options"), "DENY", status)
            self.assertEqual(headers.get("Content-Security-Policy"), "frame-ancestors 'none'", status)

    def test_generation_drops_fetch_started_before_close(self):
        started, gate, calls = threading.Event(), threading.Event(), []

        def fetch():
            calls.append(1)
            if len(calls) == 1:
                started.set()
                gate.wait(2)
            return {"repo": "o/r", "n": len(calls)}
        c = server.Cache(fetch, 60)
        t = threading.Thread(target=c.get)
        t.start()
        started.wait(2)
        c.invalidate()                     # 取得の途中で close があった
        gate.set()
        t.join()
        self.assertEqual(c.get()[0]["n"], 2)   # ttl 内でも、その取得の結果を新しいとみなさず取り直す
        self.assertEqual(c.get()[0]["n"], 2)

    def test_generation_with_refresh(self):
        """close の後の load(true) が、close 前に始まり要求の後に終わった取得を受け取らない。"""
        clock, calls = [1000.0], []

        def fetch():
            calls.append(1)
            if len(calls) == 1:
                c.invalidate()             # 取得の途中で close
                clock[0] += 5              # 終わったのは load(true) の到着より後
            return {"repo": "o/r", "n": len(calls)}
        c = server.Cache(fetch, 60, lambda: clock[0])
        c.get()
        self.assertEqual(c.get(refresh=True)[0]["n"], 2)

    def test_read_failure_is_502(self):
        with self.assertRaises(cmd.FetchError):
            pclose.progress_gh.fetch_issue_state("o/r", 30, lambda argv: (1, "not json", "boom"))

    def test_read_graphql_errors_with_exit_0(self):
        """#216: exit 0 で NOT_FOUND 以外の errors が来たら、その message を出す（「終了コード 0」にしない）。"""
        out = json.dumps({"data": {"repository": None},
                          "errors": [{"type": "FORBIDDEN", "message": "Resource not accessible by integration"}]})
        with self.assertRaises(cmd.FetchError) as ctx:
            pclose.progress_gh.fetch_issue_state("o/r", 30, lambda argv: (0, out, ""))
        self.assertIn("Resource not accessible by integration", str(ctx.exception))
        self.assertNotIn("終了コード", str(ctx.exception))
        self.assertEqual(pclose.perform(30, "o/r", Runner(read=(0, out, "")))[::2], (502, False))


if __name__ == "__main__":
    unittest.main()
