"""進捗一覧 web server（scripts/progress/）の回帰テスト。

fixture と差し込みの取得関数だけで動く（ネットワーク・git 不要、1 秒未満）。
対応する判定は .spec/issues/176-progress-server.md §7 の V2〜V8。
"""

import http.client
import importlib
import json
import sys
import threading
import unittest
from pathlib import Path

PROGRESS = Path(__file__).resolve().parents[1] / "progress"
sys.path.insert(0, str(PROGRESS))   # モジュールどうしが同じディレクトリから import し合うため
github, local_git, server, tree = (importlib.import_module(m) for m in ("github", "local_git", "server", "tree"))

REPO = "o/r"
SECTIONS = tree.label_sections((PROGRESS.parent / "setup-labels.sh").read_text())


def issue(num, labels=(), state="OPEN", parent=None, reason=None, title=None, parent_repo=REPO):
    return {"number": num, "title": title or f"t{num}", "state": state, "stateReason": reason,
            "url": f"https://x/{num}", "updatedAt": "2026-10-23T00:00:00Z",
            "labels": {"totalCount": len(labels), "nodes": [{"name": x} for x in labels]},
            "parent": {"number": parent, "repository": {"nameWithOwner": parent_repo}} if parent else None,
            "closedByPullRequestsReferences": {"totalCount": 0, "nodes": []}}


ISSUES = [
    issue(1, ["epic"]),
    issue(2, ["task"], parent=1),
    issue(12, ["bug"], parent=2),                      # fix/12-x
    issue(13, ["feature"], parent=2),                  # 次の候補
    issue(14, ["feature", "user-action"], parent=2),   # 要対応
    issue(15, ["feature"], state="CLOSED", parent=2, reason="COMPLETED"),   # ブランチが残っている
    issue(16, ["feature"], state="CLOSED", parent=2, reason="NOT_PLANNED"),
    issue(756, ["task"], parent=1),
    issue(770, ["survey"], parent=756),                # survey/756-i770
    issue(30, ["epic"], parent=1),                     # sub-epic（逸脱ではない）
    issue(40, ["review-integrity"]),                   # 報告 issue（逸脱ではない）
    issue(41, ["enhancement"]),                        # テンプレート外のラベル
    issue(50, ["feature"], parent=1),                  # 逸脱: epic 直下の issue 層
    issue(51, ["feature", "bug"], parent=2),           # 逸脱: 種類ラベル 2 個
    issue(60, ["feature"], parent=12, parent_repo="other/repo"),    # 親が別 repo（番号は手元の #12 と同じ）
    issue(70, ["docs"], title="<script>alert(1)</script>"),
]
BRANCHES = ["fix/12-x", "feature/15-old", "survey/756-i770", "pre-task/20261023-1", "main"]
WORKTREES = [{"path": "/w/issue770", "branch": "survey/756-i770", "prunable": False},
             {"path": "/w/gone", "branch": "fix/12-x", "prunable": True}]


def built(**kw):
    args = {"branches": BRANCHES, "worktrees": WORKTREES}
    args.update(kw)
    return tree.build(ISSUES, REPO, SECTIONS, **args)


class TreeRules(unittest.TestCase):
    def test_v3_working(self):
        n = built()["nodes"]
        self.assertTrue(n[12]["working"])                           # fix/ を取りこぼさない
        self.assertTrue(n[770]["working"])                          # task 単位: 2 つ目の番号が issue
        self.assertFalse(n[756]["working"])                         # task 番号は作業中にしない
        self.assertEqual(n[756]["taskBranches"], ["survey/756-i770"])
        self.assertFalse(n[15]["working"])                          # closed + ブランチ → 残骸
        self.assertIn("残骸（closed なのにブランチ・worktree が残っている）", n[15]["notes"])
        self.assertEqual(n[770]["worktrees"], ["/w/issue770"])
        self.assertEqual(n[12]["worktrees"], [])                    # prunable は根拠にしない

    def test_v3_branch_forms(self):
        self.assertEqual(tree.branch_issue("survey/756-i770"), (770, 756))
        self.assertEqual(tree.branch_issue("fix/12-x"), (12, None))
        self.assertIsNone(tree.branch_issue("main"))
        # 形に合っても、番号が一覧に無いブランチは捨てる（pre-task/<日付>-… 等）
        self.assertNotIn("pre-task/20261023-1", [b for n in built()["nodes"].values() for b in n["branches"]])

    def test_v3_git_unknown(self):
        r = built(branches=None, worktrees=None, git_error="git が無い")
        self.assertIsNone(r["nodes"][12]["working"])
        self.assertIsNone(r["summary"]["working"])
        self.assertEqual(r["gitError"], "git が無い")

    def test_v4_marks(self):
        n = built()["nodes"]
        self.assertIn("epic の直下に issue 層がある（task を挟む）", n[50]["marks"])
        self.assertIn("種類ラベルが 2 個以上: feature, bug", n[51]["marks"])
        self.assertIn("親 other/repo#12 が一覧に無い", n[60]["marks"])
        self.assertNotIn(60, n[12]["children"])
        self.assertEqual(n[40]["notes"], [])                       # 報告 issue に「種類ラベルなし」を付けない
        for ok in (1, 2, 12, 30, 40, 41, 770):                     # 正常（sub-epic・報告・テンプレート外）
            self.assertEqual(n[ok]["marks"], [], ok)
        self.assertIn("テンプレート外のラベル: enhancement", n[41]["notes"])

    def test_tree_and_progress(self):
        r = built()
        self.assertIn(60, r["roots"])
        self.assertEqual(r["nodes"][1]["children"], [2, 756, 30, 50])
        self.assertEqual(r["nodes"][2]["progress"], {"completed": 1, "total": 5, "notPlanned": 1})
        self.assertIn("子なし", r["nodes"][30]["notes"])

    def test_v8_summary(self):
        s = built()["summary"]
        self.assertEqual(s["needsUser"], [14])
        self.assertEqual(sorted(s["working"]), [12, 770])
        self.assertEqual(sorted(s["next"]), [13, 51])


class Fetch(unittest.TestCase):
    def page(self, nums, total):
        return {"data": {"repository": {"issues": {"totalCount": total, "nodes": [issue(n) for n in nums]}}}}

    def test_v2_dedup_and_total(self):
        self.assertEqual([x["number"] for x in github.collect([self.page([2, 1], 3), self.page([3, 2], 3)])], [1, 2, 3])

    def test_v7_partial_is_error(self):
        with self.assertRaises(github.FetchError):
            github.collect([self.page([1, 2], 5)])
        with self.assertRaises(github.FetchError):
            github.collect([self.page([1], 2), {"errors": [{"message": "boom"}]}])

    def test_worktree_porcelain(self):
        text = "worktree /m\nHEAD a\nbranch refs/heads/main\n\nworktree /w\nHEAD b\ndetached\nprunable gitdir file points to non-existent location\n"
        self.assertEqual(local_git.parse_worktrees(text), [
            {"path": "/m", "branch": "main", "prunable": False}, {"path": "/w", "branch": None, "prunable": True}])

    def test_remote_branches(self):
        out = "refs/heads/fix/12-x\nrefs/remotes/origin/fix/12-x\nrefs/remotes/origin/HEAD\nrefs/remotes/origin/feature/9-y\n"
        self.assertEqual(local_git.read_branches(lambda argv: out), ["feature/9-y", "fix/12-x"])


class Server(unittest.TestCase):
    def start(self, fetch):
        srv, cache = server.serve(0, 60, fetch)
        port = srv.server_address[1]
        srv.RequestHandlerClass = server.make_handler(cache, port)
        threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        return port, cache

    def req(self, port, method="GET", path="/api/tree.json", host=None):
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        c.request(method, path, headers={"Host": host or f"127.0.0.1:{port}"})
        r = c.getresponse()
        return r.status, r.read()

    def test_v5_read_only_and_host(self):
        port, _ = self.start(lambda: built())
        for m in ("POST", "PUT", "DELETE"):
            self.assertEqual(self.req(port, m)[0], 405)
        self.assertEqual(self.req(port, host="evil.example:80")[0], 403)
        self.assertEqual(self.req(port, path="/")[0], 200)

    def test_v6_escape(self):
        port, _ = self.start(lambda: built())
        status, body = self.req(port)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["nodes"]["70"]["title"], "<script>alert(1)</script>")
        self.assertNotIn("innerHTML", (PROGRESS / "index.html").read_text())

    def test_v7_stale_and_502(self):
        calls = {"n": 0}

        def flaky():
            calls["n"] += 1
            if calls["n"] > 1:
                raise github.FetchError("2 ページ目で失敗")
            return built()
        port, _ = self.start(flaky)
        self.assertEqual(self.req(port)[0], 200)
        status, body = self.req(port, path="/api/tree.json?refresh=1")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["error"], "2 ページ目で失敗")

        def broken():
            raise github.FetchError("gh が無い")
        port2, _ = self.start(broken)
        status, body = self.req(port2)
        self.assertEqual(status, 502)
        self.assertEqual(json.loads(body)["error"], "gh が無い")

    def test_empty_repo(self):
        port, _ = self.start(lambda: tree.build([], REPO, SECTIONS, [], []))
        self.assertEqual(self.req(port)[0], 200)

    def test_no_write_commands_in_code(self):
        for f in PROGRESS.glob("*.py"):
            text = f.read_text()
            for bad in ("issue edit", "issue close", "-X POST", "--method"):
                self.assertNotIn(bad, text, f.name)


if __name__ == "__main__":
    unittest.main()
