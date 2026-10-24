"""進捗の木の規則と取得（scripts/progress/）の回帰テスト。

fixture だけで動く（ネットワーク・git 不要）。対応する判定は .spec/issues/176-progress-server.md §7 の V2〜V4・V8。
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import (
    BASE,
    ISSUES,
    NOW,
    REFS,
    REPO,
    UNMERGED,
    WORKTREES,
    built,
    cmd,
    gh,
    git,
    issue,
    tree,
)


class TreeRules(unittest.TestCase):
    def test_v3_working(self):
        n = built()["nodes"]
        self.assertTrue(n[12]["working"])                           # fix/ を取りこぼさない
        self.assertTrue(n[770]["working"])                          # task 単位: 2 つ目の番号が issue
        self.assertFalse(n[756]["working"])                         # task 番号は作業中にしない
        self.assertTrue(n[756]["workingBelow"])                     # 配下の #770 が作業中
        self.assertFalse(n[15]["working"])                          # closed + ブランチ → 残骸
        self.assertIn("残骸（closed なのにブランチ・worktree が残っている）", n[15]["notes"])
        self.assertEqual(n[770]["worktrees"], ["/w/task756"])
        self.assertEqual(n[12]["worktrees"], [])                    # prunable は根拠にしない

    def test_v3_branch_forms(self):
        self.assertEqual(tree.branch_issue("survey/756-i770"), (770, 756))
        self.assertEqual(tree.branch_issue("fix/12-x"), (12, None))
        self.assertEqual(tree.branch_issue("fix/12"), (12, None))
        self.assertIsNone(tree.branch_issue("pre-task/2026-1"))
        self.assertIsNone(tree.branch_issue("pre-epic/12-x"))
        self.assertIsNone(tree.branch_issue("main"))

    def test_v3_git_unknown(self):
        r = built(refs=None, worktrees=None, git_error="git が無い")
        self.assertIsNone(r["nodes"][12]["working"])
        self.assertEqual(r["summary"], {"needsUser": [14, 92], "working": None, "next": None})
        self.assertEqual(r["gitError"], "git が無い")

    def test_v4_marks(self):
        n = built()["nodes"]
        expect = {50: "epic の直下に issue 層がある（task を挟む）", 51: "種類ラベルが 2 個以上: feature, bug",
                  60: "親 other/repo#12 が一覧に無い", 71: "task の親が epic でない",
                  72: "epic と task が両方付いている", 74: "一覧の上限（labels 20 / PR 10）を超えている",
                  100: "親子が循環している"}
        for num, mark in expect.items():
            self.assertIn(mark, n[num]["marks"], num)
        self.assertNotIn(60, n[12]["children"])
        for ok in (1, 2, 12, 30, 40, 41, 770, 756, 101):            # 正常（sub-epic・報告・テンプレート外）
            self.assertEqual(n[ok]["marks"], [], ok)
        self.assertEqual(n[40]["notes"], ["報告 issue"])
        self.assertIn("テンプレート外のラベル: enhancement", n[41]["notes"])
        self.assertEqual(n[72]["kind"], "epic")

    def test_v4_no_label_checks_without_sections(self):
        n = tree.build(ISSUES, REPO, {}, REFS, WORKTREES, [], BASE, NOW, UNMERGED)["nodes"]
        self.assertEqual(n[51]["marks"], [])
        self.assertEqual(n[41]["notes"], [])

    def test_tree_and_progress(self):
        r = built()
        n = r["nodes"]
        self.assertIn(60, r["roots"])
        self.assertIn(100, r["roots"])
        self.assertEqual(n[1]["children"], [2, 756, 30, 50, 80, 90, 95, 110, 120, 122])
        self.assertEqual(n[2]["progress"], {"completed": 1, "total": 5, "notPlanned": 1})
        self.assertEqual(n[80]["progress"], {"completed": 0, "total": 0, "notPlanned": 2})
        self.assertEqual(n[1]["progress"], {"completed": 4, "total": 16, "notPlanned": 4})
        self.assertEqual(n[95]["progress"], {"completed": 0, "total": 2, "notPlanned": 1})
        self.assertTrue(n[30]["anomaly"])
        self.assertNotIn("子なし", n[30]["notes"])

    def test_v8_summary(self):
        s = built()["summary"]
        self.assertEqual(s["needsUser"], [14, 92])
        self.assertEqual(sorted(s["working"]), [12, 770])
        self.assertEqual(s["next"], [97])


class Fetch(unittest.TestCase):
    def page(self, nums, total):
        return {"data": {"repository": {"issues": {"totalCount": total, "nodes": [issue(n) for n in nums]}}}}

    def test_v2_dedup_and_total(self):
        self.assertEqual([x["number"] for x in gh.collect([self.page([2, 1], 3), self.page([3, 2], 3)])], [1, 2, 3])

    def test_v7_partial_is_error(self):
        with self.assertRaisesRegex(cmd.FetchError, "件数"):
            gh.collect([self.page([1, 2], 5)])
        with self.assertRaisesRegex(cmd.FetchError, "boom"):
            gh.collect([self.page([1], 2), {**self.page([2], 2), "errors": [{"message": "boom"}]}])

    def test_fetch_issues_through_runner(self):
        out = json.dumps([self.page([1], 2), self.page([2], 2)])
        seen = []
        self.assertEqual(len(gh.fetch_issues("o/r", lambda argv: seen.append(argv) or out)), 2)
        self.assertIn("--slurp", seen[0])
        with self.assertRaises(cmd.FetchError):
            gh.fetch_issues("o/r", lambda argv: "not json")
        with self.assertRaises(cmd.FetchError):
            gh.current_repo(lambda argv: "\n")

    def test_worktree_porcelain(self):
        text = "worktree /m\nHEAD a\nbranch refs/heads/main\n\nworktree /w x\nHEAD b\ndetached\nlocked\nprunable gone\n"
        self.assertEqual(git.parse_worktrees(text), [
            {"path": "/m", "branch": "main", "prunable": False}, {"path": "/w x", "branch": None, "prunable": True}])

    def test_remote_refs(self):
        out = ("refs/heads/fix/12-x\ta\t10\nrefs/remotes/origin/fix/12-x\tb\t20\n"
               "refs/remotes/origin/HEAD\tc\t30\nrefs/remotes/origin/feature/9-y\td\t40\n")
        self.assertEqual(git.read_refs(lambda argv: out), [
            {"refname": "refs/heads/fix/12-x", "name": "fix/12-x", "oid": "a", "time": 10},
            {"refname": "refs/remotes/origin/fix/12-x", "name": "fix/12-x", "oid": "b", "time": 20},
            {"refname": "refs/remotes/origin/feature/9-y", "name": "feature/9-y", "oid": "d", "time": 40}])

    def test_refs_follow_the_format(self):
        """偽の git は argv の --format から行を作る（書式と読み手のずれ・リモートの抜けを検出する）。"""
        def fake(argv):
            fmt = next(a for a in argv if a.startswith("--format="))[len("--format="):]
            rows = [("refs/heads/fix/12-x", "a", "10"), ("refs/remotes/origin/fix/12-x", "b", "20")]
            rows = [r for r in rows if any(r[0].startswith(p + "/") for p in argv if p.startswith("refs/"))]
            return "".join(fmt.replace("%09", "\t").replace("%(refname)", r).replace("%(objectname)", o)
                           .replace("%(committerdate:unix)", t) + "\n" for r, o, t in rows)
        self.assertEqual([(r["refname"], r["time"]) for r in git.read_refs(fake)],
                         [("refs/heads/fix/12-x", 10), ("refs/remotes/origin/fix/12-x", 20)])
        self.assertEqual(git.read_unmerged("refs/remotes/origin/main", fake),
                         {"refs/heads/fix/12-x", "refs/remotes/origin/fix/12-x"})
        with self.assertRaises(cmd.FetchError):                  # 崩れた行は黙って捨てない
            git.read_refs(lambda argv: "refs/heads/x a\n")

    def test_read_base(self):
        """rev-parse の終了コード 1 だけが「無い」。それ以外は git の失敗。"""
        self.assertEqual(git.read_base(lambda argv: (0, "x", "")), "refs/remotes/origin/main")
        self.assertEqual(git.read_base(lambda argv: (1 if "origin" in argv[-1] else 0, "", "")), "refs/heads/main")
        self.assertIsNone(git.read_base(lambda argv: (1, "", "")))
        with self.assertRaises(cmd.FetchError):
            git.read_base(lambda argv: (128, "", "fatal: not a git repository"))


if __name__ == "__main__":
    unittest.main()
