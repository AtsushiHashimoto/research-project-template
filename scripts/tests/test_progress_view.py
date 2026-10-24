"""表示の木（scripts/progress/progress_view.py）の回帰テスト。

fixture だけで動く（ネットワーク・git 不要）。対応する判定は .spec/issues/194-progress-collapse.md §6 の W1〜W5。
"""

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import built, pview


def walk(items):
    for it in items:
        yield it
        yield from walk(it["children"])


def all_items(v):
    return list(walk(v["epics"])) + list(walk(v["lone"]["items"]))


def numbers(v):
    return [it["number"] for it in all_items(v)]


def find(v, num):
    return next(it for it in all_items(v) if it["number"] == num)


def paths(v):
    """出る行の (親の番号, 番号) の組。根の親は None。"""
    out = set()

    def rec(items, parent):
        for it in items:
            out.add((parent, it["number"]))
            rec(it["children"], it["number"])
    rec(v["epics"], None)
    rec(v["lone"]["items"], "lone")
    return out


class ViewRules(unittest.TestCase):
    def setUp(self):
        self.t = built()
        self.open = pview.view(self.t)
        self.all = pview.view(self.t, closed=True)

    def test_w1_initial(self):
        v = self.open
        self.assertEqual({it["number"] for it in v["epics"]}, {1, 72})
        self.assertEqual({it["number"] for it in v["lone"]["items"]}, {40, 41, 60, 70, 71, 74, 100, 141})
        self.assertEqual(v["lone"]["count"], 8)
        self.assertFalse(v["lone"]["defaultOpen"])
        self.assertTrue(all(not it["defaultOpen"] for it in all_items(v)))
        self.assertEqual(v["query"], {"closed": False, "label": "", "q": ""})

    def test_w2_open_at(self):
        n = self.t["nodes"]
        for it in all_items(self.all):
            self.assertEqual(it["openAt"], {"epic": 1, "task": 2, "issue": 3}[n[it["number"]]["kind"]])

    def test_w3_count_and_progress(self):
        self.assertEqual(find(self.open, 2)["count"], 4)
        self.assertEqual(find(self.all, 2)["count"], 6)
        for v in (self.open, self.all):
            self.assertEqual(find(v, 2)["progress"], {"completed": 1, "total": 5, "notPlanned": 1})
        full = self.t["nodes"][1]["progress"]
        self.assertEqual(find(self.open, 1)["progress"], {"completed": full["completed"] - 2, "total": full["total"] - 2,
                                                          "notPlanned": full["notPlanned"]})
        for it in all_items(self.all):
            self.assertEqual(it["progress"], self.t["nodes"][it["number"]]["progress"], it["number"])
        for it in all_items(self.open):
            self.assertEqual(it["count"], len(it["children"]))

    def test_w4_closed_hidden_and_lifted(self):
        nodes, nums = self.t["nodes"], numbers(self.open)
        self.assertTrue(all(nodes[x]["state"] == "OPEN" for x in nums))
        self.assertEqual(sorted(nums), sorted(x for x, n in nodes.items() if n["state"] == "OPEN"))
        kids1 = [it["number"] for it in find(self.open, 1)["children"]]
        self.assertEqual(kids1, [2, 756, 30, 50, 81, 90, 95, 111])   # #81 は #80 の位置、#111 は #110 の位置
        self.assertEqual(find(self.open, 81)["liftedFrom"], 80)
        self.assertEqual(find(self.open, 111)["liftedFrom"], 110)
        self.assertEqual(find(self.open, 141)["liftedFrom"], 140)
        self.assertIsNone(find(self.open, 2)["liftedFrom"])
        for gone in (120, 121, 122, 130, 131):
            self.assertNotIn(gone, nums)
        self.assertEqual(sorted(numbers(self.all)), sorted(nodes))
        self.assertTrue(all(it["liftedFrom"] is None for it in all_items(self.all)))

    def filtered(self, **kw):
        return pview.view(self.t, **kw)

    def test_w5_filtering(self):
        v = self.filtered(q="#770")
        self.assertEqual(paths(v), {(None, 1), (1, 756), (756, 770)})
        self.assertTrue(find(v, 1)["defaultOpen"] and find(v, 756)["defaultOpen"])
        self.assertFalse(find(v, 770)["defaultOpen"])
        self.assertEqual(find(v, 770)["count"], 0)
        self.assertEqual(paths(self.filtered(label="blocked")), {(None, 1), (1, 90), (90, 92)})
        v = self.filtered(q="#2")
        self.assertEqual(paths(v), {(None, 1), (1, 2)})
        self.assertEqual(find(v, 2)["count"], 0)
        v = self.filtered(q="#80")
        self.assertEqual((v["epics"], v["lone"]["items"]), ([], []))
        v = self.filtered(q="#40")
        self.assertEqual(v["epics"], [])
        self.assertEqual([it["number"] for it in v["lone"]["items"]], [40])
        self.assertTrue(v["lone"]["defaultOpen"])
        self.assertEqual(paths(self.filtered(q=" #81 ")), {(None, 1), (1, 81)})
        self.assertEqual(numbers(self.filtered(q="#80", closed=True)), [1, 80])
        self.assertIn(70, numbers(self.filtered(q="<SCRIPT>")))          # タイトルの部分一致（小文字化）
        self.assertEqual(numbers(self.filtered(q="#abc")), [])          # 番号の形でなければタイトルの部分一致

    def test_postconditions(self):
        before = copy.deepcopy(self.t)
        for kw in ({}, {"closed": True}, {"q": "#770"}, {"label": "blocked", "closed": True}):
            nums = numbers(pview.view(self.t, **kw))
            self.assertEqual(len(nums), len(set(nums)), kw)
            self.assertTrue(set(nums) <= set(self.t["nodes"]), kw)
        self.assertEqual(self.t, before)


if __name__ == "__main__":
    unittest.main()
