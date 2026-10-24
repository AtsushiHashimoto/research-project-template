"""進捗一覧の画面（scripts/progress/page.js と index.html）の回帰テスト。

page.js を最小限の DOM の stub（progress_page_harness.js）の上で node で動かす（ブラウザ・ネットワーク不要）。
対応する判定は .spec/issues/194-progress-collapse.md §6 の W7（W2 の一括・W4 の削除・取得）と、
.spec/issues/201-progress-cards.md §9 の W1（K1〜K8）・W2（日付）・W5（画面側の close）・W7（B1〜B3）。
CSS と文言の静的な検査（Static）は node が無くても走る。
"""

import json
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_fixture import PROGRESS, built_cards, gh, pview

HERE = Path(__file__).resolve().parent
PAGE = (PROGRESS / "index.html").read_text(encoding="utf-8")
SCRIPT = (PROGRESS / "page.js").read_text(encoding="utf-8")
CSS = re.search(r"<style>(.*?)</style>", PAGE, re.DOTALL).group(1)
CHIPS = ["異常: 子なし", "要対応", "blocked", "作業中", "配下で作業中", "30日動きなし", "子は全部完了扱い", "完了扱い", "完了", "見送り"]


def rule(selector):
    """CSS の selector の宣言（最初に一致した 1 つ）。"""
    m = re.search(r"(?:^|\n)" + re.escape(selector) + r" \{([^}]*)\}", CSS)
    return m.group(1) if m else ""


def payload(**kw):
    t = built_cards()
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
        loads = {"0||": cls.base, "0||#770": payload(q="#770"), "0||#2": payload(q="#2"), "0||#40": payload(q="#40"),
                 "1|blocked|x": payload(closed=True, label="blocked", q="x"), "0|nosuch|": payload(label="nosuch")}
        cls.buttons = [[int(lv), text] for lv, text in
                       re.findall(r'<button type="button" data-level="(\d)">([^<]+)</button>', PAGE)]
        loads["1||"] = loads["0||"]          # close の後の取り直し（refresh=1 は鍵に入れない）
        r = subprocess.run([node, str(HERE / "progress_page_harness.js")], capture_output=True, text=True, timeout=10, check=False,
                           env={**os.environ, "TZ": "UTC"},   # 日付の JST は端末の時刻帯に依らない（K6）
                           input=json.dumps({"script": SCRIPT, "payloads": loads, "buttons": cls.buttons,
                                             "close": {"status": 200, "body": {"closed": 30}}}))
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
            if v["lone"]["openAt"] <= lv and v["lone"]["count"]:
                want.add("lone")
            self.assertEqual(set(self.out["levels"][str(lv)]), want, lv)
        self.assertEqual(self.out["levels"]["0"], [])

    def test_bulk_clears_rows_keeps_summary(self):
        self.assertEqual(self.out["afterLateToggles"], [])   # 一括で開いた行の toggle を記録しない
        self.assertEqual(self.out["toggledBefore"], {"row": True, "sum": False})
        self.assertEqual(self.out["toggledAfter"], {"row": False, "sum": False})

    def test_filter_resets_level_and_rows(self):
        self.assertEqual(self.out["filterOpened"], ["1", "756"])   # 段 1 で閉じた #1 の記録は消え、経路が開く
        self.assertEqual(self.out["clearedOpened"], [])            # 段も 0 に戻る
        self.assertEqual(self.out["loneOpened"], ["lone"])         # lone.defaultOpen

    def test_stale_response_is_dropped(self):
        self.assertEqual(self.out["staleUrls"], ["/api/tree.json?closed=0&label=&q=%23770",
                                                 "/api/tree.json?closed=0&label=&q=%232"])
        self.assertEqual(self.out["staleShown"], [1, 2])          # #770 の経路（#756・#770）は描かない
        self.assertEqual(self.out["staleOpened"], ["1"])

    def test_load_url_carries_query(self):
        self.assertEqual(self.out["firstUrl"], "/api/tree.json?closed=0&label=&q=")
        self.assertEqual(self.out["filteredUrl"], "/api/tree.json?closed=1&label=blocked&q=x")
        self.assertIn("一致なし", self.out["filteredText"])
        self.assertEqual(self.out["unknownLabelUrls"][:2], ["/api/tree.json?closed=0&label=nosuch&q=",
                                                             "/api/tree.json?closed=0&label=&q="])
        self.assertIn("取得失敗 — 下は前の条件の表示", self.out["failBanner"])   # 描き直しでも消えない

    def test_b1_b2_pressed_and_state(self):
        b = self.out["bulk"]
        order = [lv for lv, _ in self.buttons]
        for lv in range(4):
            self.assertEqual(b[str(lv)]["pressed"], ["true" if x == lv else "false" for x in order], lv)
        self.assertEqual(b["0"]["text"], "すべて閉じている · 再適用")       # 初期が段 0 なので、押すと再適用
        self.assertEqual(b["1"]["text"], f"epic まで · 開いている {b['1']['visible']} 行")
        self.assertEqual(b["3"]["text"], f"すべて · 開いている {b['3']['visible']} 行")
        self.assertGreater(b["3"]["visible"], b["1"]["visible"])
        t = b["toggled"]
        self.assertEqual(t["pressed"], ["false"] * 4)                       # 押された段と実際の開閉が食い違う
        self.assertEqual(t["text"], f"epic まで · 開いている {t['visible']} 行 · 手で変えた 1 行")
        f = b["filtered"]
        self.assertEqual(f["pressed"], ["false"] * 4)
        self.assertEqual(f["text"], f"一致への経路だけ開いている · 開いている {f['visible']} 行")

    def test_b3_reapply(self):
        b = self.out["bulk"]
        self.assertEqual(b["reapplied"], b["3"]["text"] + " · 再適用")
        self.assertEqual(b["afterReapply"]["text"], b["1"]["text"])   # 手で変えた行の記録が消え、文言が変わる（再適用は付かない）
        self.assertEqual(b["afterReapply"]["pressed"], [str(lv == 1).lower() for lv, _ in self.buttons])

    def test_k1_card_structure(self):
        cards = self.out["cards"]
        self.assertTrue(any(c["tag"] == "DETAILS" for c in cards) and any(c["tag"] == "DIV" for c in cards))
        for c in cards:
            if c["tag"] == "DETAILS":
                self.assertEqual(c["first"], "SUMMARY", c)
                self.assertTrue(all("card" in x.split() for x in c["outside"]), c)   # 子のカードは summary の外
            self.assertEqual(c["inner"][:2], ["head", "meta"], c)
            self.assertTrue(set(c["inner"]) <= {"head", "meta", "confirm"}, c)

    def test_k4_chips_fixed_and_ordered(self):
        by = {c["key"]: c["chips"] for c in self.out["cards"]}
        for key, chips in by.items():
            self.assertTrue(set(chips) <= set(CHIPS), (key, chips))
            self.assertEqual(chips, sorted(chips, key=CHIPS.index), key)
        self.assertEqual(by[30], ["異常: 子なし"])
        self.assertEqual(by[14], ["要対応"])
        self.assertEqual(by[95], ["配下で作業中", "30日動きなし"])
        self.assertEqual(by[96], ["作業中"])
        self.assertEqual(by[180], ["子は全部完了扱い"])

    def test_k6_meta_dates_in_jst(self):
        by = {c["key"]: c["meta"] for c in self.out["cards"]}
        self.assertEqual(by[190], "更新 10-21 · 作成 2025-12-31")      # 15:30Z は JST で翌日、前年は年付き
        self.assertEqual(by[13], "更新 10-23 · 作成 01-05 · PR #301 merged +1 · コミット 10-04")
        self.assertEqual(by[12], "更新 10-23 · 作成 01-05 · PR #302 merged · コミット 10-21")

    def test_w5_close_needs_second_press(self):
        c = self.out["close"]
        self.assertTrue(c["prevented"])                  # <summary> の中でもカードを開閉しない
        self.assertEqual((c["postsAfterFirst"], c["confirm"], c["focused"]), (0, True, "やめる"))
        self.assertFalse(c["afterEscape"])
        self.assertEqual(c["posts"], [{"url": "/api/close", "method": "POST", "body": '{"number":30}',
                                       "headers": {"Content-Type": "application/json", "X-Progress-Close": "1"}}])
        self.assertEqual(c["reload"], ["/api/tree.json?closed=0&label=&q=&refresh=1"])
        self.assertFalse(c["afterSend"])

    def test_closed_hint_removed(self):
        self.assertNotIn("+${hidden} closed", PAGE)
        self.assertNotIn('closed: "1"', SCRIPT)


class Static(unittest.TestCase):
    """201 §5-1 の K2・K3・K5〜K8 と B1 の CSS（node なしで走る）。"""

    def test_k2_no_body(self):
        for q in (gh.QUERY, gh.PULL_QUERY):
            self.assertNotRegex(q, r"\bbody\b")

    def test_k3_head_wraps(self):
        self.assertIn("flex-wrap:wrap", rule(".head"))
        self.assertIn("margin-left:auto", rule(".right"))
        self.assertIn("flex-wrap:wrap", rule(".right"))

    def test_k5_k6_k7_type_and_color(self):
        self.assertIn("border-color:var(--warn)", rule(".c-anom"))
        self.assertIn("border:none", rule(".c-stale"))
        self.assertIn("color:var(--muted)", rule(".c-stale"))
        self.assertIn("font-size:12px", rule(".badge"))
        meta = rule(".meta")
        self.assertTrue(all(x in meta for x in ("display:block", "font-size:12px", "color:var(--muted)")), meta)
        title = rule(".head .title")
        self.assertIn("font-size:14px", title)
        self.assertIn("font-weight:400", title)
        heavy = [m.group(1).strip().split("\n")[-1] for m in re.finditer(r"([^{}]*)\{[^}]*font-weight:\s*([6-9]00|bold)", CSS)]
        self.assertEqual(heavy, [".group summary"])   # h1 は既定の太さ
        body = re.sub(r"(?s)@media[^{]*\{.*?\n\}\n|:root \{[^}]*\}", "", CSS)
        self.assertNotRegex(body, r"#[0-9a-fA-F]{3,6}\b|rgb|hsl|transparent")   # 色は :root の変数だけ

    def test_k8_card_box(self):
        card = rule("#tree .card")
        for x in ("background:var(--card)", "border-radius:8px", "padding:6px 10px", "margin:4px 0"):
            self.assertIn(x, card)
        nested = rule("#tree .card .card, #tree .lone > .card")
        self.assertIn("margin-left:12px", nested)
        self.assertIn("border-left:1px solid var(--line)", nested)

    def test_b1_pressed_css_and_status(self):
        pressed = rule('#bulk button[aria-pressed="true"]')
        self.assertIn("background:var(--work)", pressed)
        self.assertIn("color:var(--bg)", pressed)
        self.assertIn('<span id="bulk-state" role="status"></span>', PAGE)
        self.assertIn('<script src="/page.js"></script>', PAGE)
        self.assertNotIn("referrerpolicy", PAGE)


if __name__ == "__main__":
    unittest.main()
