"""進捗一覧の起動スクリプト（scripts/progress/ensure.py）のテスト。.spec/issues/212-progress-launcher.md §5 の E1〜E6。

実際に listen するのは E4・E5 の 2 件だけ。E1〜E3b・E6 は git・接続・起動を差し込む。
"""

import http.server
import importlib
import json
import os
import re
import signal
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import PROGRESS, git

ensure = importlib.import_module("ensure")
COMMON = "/x/repo/.git"


def ident(common=COMMON, app="progress", pid=4242):
    return ("http", 200, json.dumps({"app": app, "commonDir": common, "pid": pid}).encode())


def fake_git(config=None, origin=None):
    """git config --get progress.port と git remote get-url origin の結果を差し込む。"""
    def runner(argv):
        if argv[:2] == ["git", "config"]:
            return (0, config + "\n", "") if config is not None else (1, "", "")
        if origin is None:
            return 2, "", "error: No such remote 'origin'\n"
        return 0, origin + "\n", ""
    return runner


class E1Formula(unittest.TestCase):
    def test_values(self):
        self.assertEqual(ensure.formula("research-project-template"), 18415)
        self.assertEqual(ensure.formula("delta-clip-dev"), 18218)
        self.assertEqual(ensure.formula("Delta-CLIP-Dev"), 18218)
        for name in ("a", "weavenet2", "x" * 300):
            self.assertTrue(ensure.PORT_MIN <= ensure.formula(name) <= ensure.PORT_MAX)


class E2Choose(unittest.TestCase):
    def test_order(self):
        both = fake_git(config="18500", origin="git@github.com:o/delta-clip-dev.git")
        self.assertEqual(ensure.choose_port("18001", both), 18001)
        self.assertEqual(ensure.choose_port(None, both), 18500)
        self.assertEqual(ensure.choose_port(None, fake_git(origin="git@github.com:o/delta-clip-dev.git")), 18218)

    def test_rejects(self):
        for bad in ("abc", "18k", "+18000", "18_000", "17999", "19000", "8765", ""):
            with self.assertRaises(ensure.Refused, msg=bad):
                ensure.choose_port(bad, fake_git())
            with self.assertRaises(ensure.Refused, msg=bad):
                ensure.choose_port(None, fake_git(config=bad, origin="https://github.com/o/r"))

    def test_origin_forms(self):
        for url in ("git@github.com:o/delta-clip-dev.git", "https://github.com/o/delta-clip-dev/",
                    "https://github.com/o/delta-clip-dev.git", "ssh://git@host:22/o/delta-clip-dev"):
            self.assertEqual(ensure.repo_name(url), "delta-clip-dev", url)

    def test_main_exit_code_and_broken_config(self):
        self.assertEqual(ensure.main(["--port", "abc"]), 2)
        def broken(argv):                                # 1 以外の失敗（壊れた設定）で式に戻さない
            return (3, "", "bad config line 1") if argv[1] == "config" else (0, "git@h:o/r.git\n", "")
        with self.assertRaises(ensure.Refused):
            ensure.choose_port(None, broken)

    def test_no_origin_does_not_use_directory(self):
        for runner in (fake_git(), fake_git(origin="")):
            with self.assertRaises(ensure.Refused) as cm:
                ensure.choose_port(None, runner)
            self.assertIn("git config progress.port", str(cm.exception))
        self.assertEqual(ensure.choose_port(None, fake_git(config="18002")), 18002)   # 上書きがあれば止まらない


class E3Classify(unittest.TestCase):
    def test_branches(self):
        self.assertEqual(ensure.classify(("refused",), COMMON), ("A", None))
        self.assertEqual(ensure.classify(ident(), COMMON)[0], "B")
        cases = [("別の repo", ident("/y/.git")), ("null", ident(None)), ("ではない", ident(app="other")),
                 ("ではない", ("http", 200, b"<html>")), ("応答なし", ("timeout",)),
                 ("古い進捗一覧", ("http", 404, b"not found\n")), ("ではない", ("error", "BadStatusLine"))]
        for word, result in cases:
            kind, why = ensure.classify(result, COMMON)
            self.assertEqual(kind, "C", result)
            self.assertIn(word, why)

    def test_realpath(self):
        with tempfile.TemporaryDirectory() as d:
            real = os.path.join(d, "real")
            os.mkdir(real)
            os.symlink(real, os.path.join(d, "link"))
            self.assertEqual(ensure.classify(ident(os.path.join(d, "link")), real)[0], "B")

    def test_c_shows_override(self):
        code, _, err = ensure.ensure(1, COMMON, "/", "/dev/null", probe=lambda: ("C", "進捗一覧ではない"),
                                     start=self.fail)
        self.assertEqual(code, 2)
        self.assertIn("git config progress.port", err)


class Child:
    def __init__(self, exit_at=None):
        self.pid, self.returncode, self.terminated, self.exit_at, self.calls = 99, None, False, exit_at, 0

    def poll(self):
        self.calls += 1
        if self.exit_at is not None and self.calls >= self.exit_at:
            self.returncode = 1
        return self.returncode

    def terminate(self):
        self.terminated = True


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, s):
        self.t += s


def seq(*kinds):
    """probe の差し込み。最後の値を繰り返す。"""
    items = list(kinds)
    return lambda: items.pop(0) if len(items) > 1 else items[0]


class E3bWaitAndStop(unittest.TestCase):
    def run_a(self, probe, child):
        """(ensure の戻り値, 子, 経過した偽の時刻, ログのパス)。"""
        clock = Clock()
        with tempfile.NamedTemporaryFile("w+", suffix=".log") as log:
            log.write("--- 前の回\n他の呼び出しの失敗\n--- この回\nTraceback 本物\n")
            log.flush()
            got = ensure.ensure(1, COMMON, "/", log.name, probe=probe, start=lambda *a: (child, "--- この回"),
                                clock=clock, sleep=clock.sleep)
            return got, child, clock.t, log.name

    def test_child_exits_then_rejudge(self):
        (code, out, _), *_ = self.run_a(seq(("A", None), ("B", {})), Child(exit_at=1))
        self.assertEqual((code, out.splitlines()[0]), (0, "http://127.0.0.1:1/"))
        (code, _, err), *_ = self.run_a(seq(("A", None), ("C", "別の repo の進捗一覧")), Child(exit_at=1))
        self.assertEqual(code, 2)
        (code, _, err), *_ = self.run_a(seq(("A", None)), Child(exit_at=1))
        self.assertEqual(code, 1)
        self.assertIn("Traceback 本物", err)
        self.assertNotIn("他の呼び出しの失敗", err)

    def test_timeout_terminates_child(self):
        (code, _, err), child, waited, log = self.run_a(seq(("A", None)), Child())
        self.assertEqual(code, 1)
        self.assertTrue(child.terminated)
        self.assertAlmostEqual(waited, 10, delta=0.3)
        self.assertIn(f"ログ: {log}", err)

    def stop(self, probe, cmdline, killed, clock=None):
        clock = clock or Clock()

        def kill(*a):
            if isinstance(killed, BaseException):
                raise killed
            killed.append(a)
        return ensure.stop(1, COMMON, probe=probe, cmdline=lambda pid: cmdline, kill=kill,
                           clock=clock, sleep=clock.sleep)

    def test_stop(self):
        ok = ["python3", "/r/scripts/progress/server.py", "--port", "1"]
        killed = []
        self.assertEqual(self.stop(seq(("A", None)), ok, killed)[0], 0)
        self.assertEqual(self.stop(seq(("C", "x")), ok, killed)[0], 2)
        self.assertEqual(self.stop(seq(("B", {"pid": 7})), ["python3", "evil.py", "--port", "1"], killed)[0], 2)
        self.assertEqual(self.stop(seq(("B", {"pid": 7})), ok[:2] + ["--port", "2"], killed)[0], 2)
        self.assertEqual(killed, [])                                   # 合わなければ送らない
        self.assertEqual(self.stop(seq(("B", {"pid": 7}), ("B", {}), ("A", None)), ok, killed)[0], 0)
        self.assertEqual(killed, [(7, signal.SIGTERM)])
        clock = Clock()
        self.assertEqual(self.stop(seq(("B", {"pid": 7})), ok, killed, clock)[0], 1)   # 5 秒で止まらない
        self.assertAlmostEqual(clock.t, 5, delta=0.2)
        self.assertEqual(self.stop(seq(("B", {"pid": 7})), [], killed)[0], 2)          # /proc を読めない
        self.assertEqual(self.stop(seq(("B", {"pid": 7}), ("A", None)), ok, ProcessLookupError())[0], 0)
        self.assertEqual(self.stop(seq(("B", {"pid": 7})), ok, PermissionError())[0], 2)


class E6Devcontainer(unittest.TestCase):
    def test_ports_attributes(self):
        key = f"{ensure.PORT_MIN}-{ensure.PORT_MAX}"
        for kind in ("cpu", "gpu"):
            text = (PROGRESS.parents[1] / ".devcontainer" / kind / "devcontainer.json").read_text(encoding="utf-8")
            conf = json.loads(re.sub(r"(?m)^\s*//.*$", "", text))
            self.assertEqual(list(conf["portsAttributes"]), [key], kind)
            self.assertIs(conf["portsAttributes"][key]["requireLocalPort"], True, kind)


class E7StartDir(unittest.TestCase):
    def test_main_worktree_or_toplevel(self):
        def runner(listing):
            calls = []
            def run(argv):
                calls.append(argv[1])
                return listing if argv[1] == "worktree" else "/w/issue1\n"
            return run, calls
        run, calls = runner("worktree /m\nHEAD 1\nbranch refs/heads/main\n\nworktree /m/w\nHEAD 2\ndetached\n")
        self.assertEqual((git.start_dir(run), calls), ("/m", ["worktree"]))   # toplevel を呼ばない
        run, calls = runner("worktree /m.git\nbare\n\nworktree /w/issue1\nHEAD 2\nbranch refs/heads/x\n")
        self.assertEqual((git.start_dir(run), calls), ("/w/issue1", ["worktree", "rev-parse"]))

    def test_main_passes_start_dir(self):
        seen = []
        with mock.patch.object(ensure, "choose_port", return_value=18001), \
             mock.patch.object(git, "common_dir", return_value=COMMON), \
             mock.patch.object(git, "start_dir", return_value="/m"), \
             mock.patch.object(ensure, "ensure", side_effect=lambda *a: seen.append(a[2]) or (0, "", "")):
            self.assertEqual(ensure.main([]), 0)
        self.assertEqual(seen, ["/m"])


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Listen(unittest.TestCase):
    def test_e4_port_used_by_other(self):
        class Quiet(http.server.BaseHTTPRequestHandler):      # 何にも 501 を返す
            def log_message(self, *args):
                pass
        srv = http.server.HTTPServer(("127.0.0.1", 0), Quiet)
        threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        code, out, err = ensure.ensure(srv.server_address[1], COMMON, "/", "/dev/null", start=self.fail)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("進捗一覧ではない", err)

    def test_e5_start_reuse_stop(self):
        port, common, cwd = free_port(), git.common_dir(), git.main_worktree()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        log = os.path.join(tmp.name, "progress-server.log")
        pids = []

        def start(*a):
            child, mark = ensure.start_server(*a)
            pids.append(child.pid)
            self.addCleanup(lambda: child.poll() is None and (child.terminate(), child.wait()))
            return child, mark
        code, out, err = ensure.ensure(port, common, cwd, log, start=start, interval=0.05)
        self.assertEqual((code, out.splitlines()[0]), (0, f"http://127.0.0.1:{port}/"), err)
        kind, info = ensure.classify(ensure.fetch_identity(port), common)
        self.assertEqual((kind, info["pid"]), ("B", pids[0]))
        self.assertIn(f"pid {pids[0]} port {port}", Path(log).read_text(encoding="utf-8"))   # その回の区切り
        self.assertEqual(ensure.ensure(port, common, cwd, log, start=self.fail)[0], 0)   # 立てない
        self.assertEqual(ensure.stop(port, common)[0], 0)
        self.assertEqual(ensure.fetch_identity(port), ("refused",))


if __name__ == "__main__":
    unittest.main()
