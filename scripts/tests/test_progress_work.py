"""作業中・完了扱い・動きなし・異常・メタ情報の規則（scripts/progress/progress_work.py）の回帰テスト。

fixture だけで動く（ネットワーク・git 不要）。対応する判定は .spec/issues/201-progress-cards.md §9 の W2〜W4・W6。
期待値は fixture（progress_fixture.CARD_*）を手で数えたもの。
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import DAY, NOW, built, built_cards, pview


def walk(items):
    for it in items:
        yield it
        yield from walk(it["children"])


def items(v):
    return {it["number"]: it for it in list(walk(v["epics"])) + list(walk(v["lone"]["items"]))}


class Working(unittest.TestCase):
    def test_w3_rules_and_boundaries(self):
        n = built_cards()["nodes"]
        expect = {12: True,    # 基準に無く 3 日前
                  770: True,   # 基準に含まれるが open の PR #303
                  13: False,   # 基準に無いが 20 日前
                  14: False,   # 2 日前だが MERGED の PR #304 の head と同じ oid（squash merge 済み）
                  51: True,    # ちょうど 14 日前は含む
                  97: False,   # 14 日 + 1 秒前は外れる
                  96: True,    # ローカルは基準に含まれ、リモートが基準に無い（ref ごと）
                  15: False}   # closed
        self.assertEqual({k: n[k]["working"] for k in expect}, expect)
        self.assertTrue(n[95]["workingBelow"] and n[2]["workingBelow"] and n[1]["workingBelow"])
        self.assertFalse(n[90]["workingBelow"])

    def test_w3_unknown_without_base_or_pulls(self):
        for kw in ({"pulls": None, "pulls_error": "落ちた"}, {"base": None}, {"refs": None, "worktrees": None}):
            r = built_cards(**kw)
            self.assertEqual({n["working"] for n in r["nodes"].values()}, {None}, kw)
            self.assertEqual({n["workingBelow"] for n in r["nodes"].values()}, {None}, kw)
            self.assertEqual((r["summary"]["working"], r["summary"]["next"]), (None, None), kw)
        self.assertEqual(built_cards(pulls=None, pulls_error="落ちた")["pullsError"], "落ちた")
        self.assertIsNone(built_cards(base=None)["rules"]["base"])

    def test_w2_prs_and_unlinked(self):
        r = built_cards()
        n = r["nodes"]
        self.assertEqual([p["number"] for p in n[12]["prs"]], [302])          # A と C の重複を除き、fork の #311 は付けない
        self.assertEqual([p["number"] for p in n[13]["prs"]], [301, 300])     # 番号の降順
        self.assertEqual(r["rules"]["unlinkedOpenPrs"], [310, 311])
        self.assertEqual(r["rules"]["workingDays"], 14)
        self.assertEqual(r["rules"]["staleDays"], 30)

    def test_w2_meta(self):
        n = built_cards()["nodes"]
        self.assertEqual(n[96]["lastCommit"], NOW - DAY)
        self.assertIsNone(n[90]["lastCommit"])
        self.assertEqual(n[190]["createdAt"], "2025-12-31T00:00:00Z")
        self.assertEqual(n[2]["steps"][2], {"step": "feature", "total": 5, "closed": 2})   # #13 #14 #15 #16 #51、closed は #15 #16
        self.assertEqual(n[756]["steps"][:2], [{"step": "survey", "total": 1, "closed": 0},
                                               {"step": "spec", "total": 1, "closed": 1}])
        self.assertIsNone(n[12]["steps"])
        self.assertIsNone(n[1]["steps"])

    def test_w2_epic_steps_count_shown_tasks_only(self):
        t = built_cards()
        pair = lambda v: [(s["total"], s["closed"]) for s in items(v)[1]["steps"]]
        # closed=False: #2 #756 #90 #95 だけ（#80 #110 #120 は closed、#150 は完了扱い）
        self.assertEqual(pair(pview.view(t)), [(2, 0), (2, 1), (2, 1), (1, 0), (1, 0)])
        # closed=True: feature に #80（未完）#110（未完）#120（済）#150（済）が加わる
        self.assertEqual(pair(pview.view(t, closed=True)), [(2, 0), (2, 1), (6, 3), (1, 0), (1, 0)])
        self.assertIsNone(items(pview.view(t))[12]["steps"])


class Hidden(unittest.TestCase):
    def test_w4_completed_like(self):
        t = built_cards()
        n = t["nodes"]
        self.assertEqual({k for k, x in n.items() if x["completedLike"]}, {150, 160, 170, 181})
        shown = items(pview.view(t))
        self.assertFalse({150, 151, 160, 161, 170, 171, 181, 182} & set(shown))
        self.assertEqual(shown[172]["liftedFrom"], 171)                       # 完了扱いの下の open の孫は持ち上がる
        self.assertTrue(n[180]["childrenCompletedLike"] and not n[180]["anomaly"])
        self.assertEqual(shown[180]["count"], 0)
        self.assertEqual(shown[1]["progress"], items(pview.view(built()))[1]["progress"])   # #150 の部分木を数えない
        everything = items(pview.view(t, closed=True))
        self.assertTrue({150, 160, 170, 181} <= set(everything))
        s = t["summary"]
        for group in s.values():
            self.assertFalse({150, 160, 170, 181} & set(group or []))

    def test_w6_stale_marks_only(self):
        t = built_cards()
        n = t["nodes"]
        self.assertEqual({k for k, x in n.items() if x["stale"]}, {97, 95, 92})   # #91 はちょうど 30 日で付かない
        self.assertTrue({97, 95, 92} <= set(items(pview.view(t))))                 # 印で消えない

    def test_w5_anomaly(self):
        n = built()["nodes"]
        self.assertEqual({k for k, x in n.items() if x["anomaly"]}, {30, 71, 72})


if __name__ == "__main__":
    unittest.main()
