"""進捗一覧の画面（scripts/progress/index.html の <script>）の回帰テスト。

<script> を抜き出し、最小限の DOM の stub（progress_page_harness.js）の上で node で動かす（ブラウザ・ネットワーク不要）。
対応する判定は .spec/issues/194-progress-collapse.md §6 の W7（W2 の一括・W4 の削除・取得）。
"""

import json
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import PROGRESS, built, pview

HERE = Path(__file__).resolve().parent
PAGE = (PROGRESS / "index.html").read_text(encoding="utf-8")


def payload(**kw):
    t = built()
    return json.loads(json.dumps({**t, "fetchedAt": "2026-10-24 00:00:00 JST", "ttl": 60, "error": None,
                                  "errorAt": None, "labelsError": None, "view": pview.view(t, **kw)}))


def walk(items):
    for it in items:
        yield it
        yield from walk(it["children"])


class Page(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        node = shutil.which("node")
        if not node:
            raise unittest.SkipTest("node が無いので画面の JS を実行できない（W7 は未検査）")
        cls.base = payload()
        loads = {"0||": cls.base, "0||#770": payload(q="#770"), "0||#2": payload(q="#2"),
                 "1|blocked|x": payload(closed=True, label="blocked", q="x")}
        script = re.search(r"<script>\n(.*?)</script>", PAGE, re.S).group(1)
        cls.buttons = [[int(lv), text] for lv, text in
                       re.findall(r'<button type="button" data-level="(\d)">([^<]+)</button>', PAGE)]
        r = subprocess.run([node, str(HERE / "progress_page_harness.js")], capture_output=True, text=True, timeout=10,
                           input=json.dumps({"script": script, "payloads": loads, "buttons": cls.buttons}))
        if r.returncode:
            raise AssertionError(r.stderr)
        cls.out = json.loads(r.stdout)

    def test_bulk_buttons(self):
        self.assertEqual(self.buttons, [[1, "epic まで開く"], [2, "task まで開く"], [3, "すべて開く"], [0, "すべて閉じる"]])
        self.assertIn('role="group" aria-label="一括の開閉"', PAGE)

    def test_levels_open_by_open_at(self):
        v = self.base["view"]
        items = list(walk(v["epics"])) + list(walk(v["lone"]["items"]))
        for lv in range(4):
            want = {str(it["number"]) for it in items if it["children"] and it["openAt"] <= lv}
            if lv >= 1 and v["lone"]["count"]:
                want.add("lone")
            self.assertEqual(set(self.out["levels"][str(lv)]), want, lv)
        self.assertEqual(self.out["levels"]["0"], [])

    def test_bulk_clears_rows_keeps_summary(self):
        self.assertEqual(self.out["toggledBefore"], {"row": True, "sum": False})
        self.assertEqual(self.out["toggledAfter"], {"row": False, "sum": False})

    def test_stale_response_is_dropped(self):
        self.assertEqual(self.out["staleUrls"], ["/api/tree.json?q=%23770", "/api/tree.json?q=%232"])
        self.assertEqual(self.out["staleShown"], [1, 2])          # #770 の経路（#756・#770）は描かない
        self.assertEqual(self.out["staleOpened"], ["1"])

    def test_load_url_carries_query(self):
        self.assertEqual(self.out["firstUrl"], "/api/tree.json")
        self.assertEqual(self.out["filteredUrl"], "/api/tree.json?closed=1&label=blocked&q=x")
        self.assertIn("一致なし", self.out["filteredText"])

    def test_closed_hint_removed(self):
        self.assertNotIn("+${hidden} closed", PAGE)
        self.assertNotIn('closed: "1"', PAGE)


if __name__ == "__main__":
    unittest.main()
