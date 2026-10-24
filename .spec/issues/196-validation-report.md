# Issue #196: validation: 進捗一覧の階層の開閉と closed の隠し方

- 実施日: 2026-10-24 JST
- 対象のコード: main = 077d619（feature #195、PR #198 マージ後）
- 仕様: `.spec/issues/194-progress-collapse.md` §6（W1〜W7。W6 は記録のみ）
- 実データ: omron-sinicx/delta-clip-dev（閲覧のみ）。**issue 657 件**（task 作成時の 639 件から増えた。W6 もこの件数で測った）、open 168 件、closed 489 件
- 以下、**下流の issue 番号は `dcd#N`**（delta-clip-dev の #N）と書く。この repo の #N と取り違えないため
- 測定スクリプトと出力は #196 のコメントに全文（一回きりの測定。恒常的なテストは増やしていない）。このファイルは判定の記録

## 判定: 判定する 6 項目のうち 5 項目は満たす。W2 は stub DOM の範囲で満たし、実ブラウザでの目視は未実施

用語: **持ち上げ** = closed の親を行として出さず、その open の子を「最も近い open の祖先」の子として、closed の親があった位置に出すこと（仕様 §3-1）。

独立の値は `view` を使わず、`progress_tree.build` の `nodes`（`parent`・`children`・`state`・`kind`）から別のコードで数えた。
画面は実ブラウザが無い（chromium・playwright なし）ので、`index.html` の `<script>` を `scripts/tests/progress_page_harness.js` の stub DOM の上で node で動かし、実データの `view` を入れて数えた。

| # | goal の項目 | 実データの結果 | 基準 | fixture のテスト | 判定 |
|---|---|---|---|---|---|
| W1 | 最初はすべて閉じ、親を持たない epic と閉じた「親なし (N)」1 行だけ | `epics` 14 件・`lone` 42 件が独立の集合と一致（差 0）、根の並びも `tree.roots` の順と一致。全 item と `lone` の `defaultOpen` が false。初期の行数 **15**（epic 14 ＋「親なし (42)」） | 差 0・開いている行 0 が合格 | `test_w1_initial` | 満たす |
| W2 | 行ごとの開閉と一括の 4 ボタン | `openAt` が epic 1・task 2・issue 3 で全件一致。開く `<details>` の数は段 0 / 1 / 2 / 3 で **0 / 15 / 37 / 38**（`view` から数えた `openAt <= level` の期待値と一致）。見える番号付きの行は **14 / 99 / 166 / 168**（「親なし」の summary は番号を持たないので数えない）。段 3 の 168 = open 168（重複 0）。行を 1 つ開くと 14 → 17、描き直しの後も開いたまま | 期待値と一致・段 3 で open 全件が合格 | `test_w2_open_at`・`test_levels_open_by_open_at`・`test_bulk_clears_rows_keeps_summary` | stub DOM の範囲で満たす。**実ブラウザでの目視は未実施** |
| W3 | 閉じた行に子の件数と進捗 | `count` の不一致 **0**。`progress` の不一致 **0**（2 通りで照合: 上から辿る写し、と葉から上へ辿る別経路）。`closed=1` で `node.progress` との不一致 **0**。件数とバッジの分母が違う行 32 件（例: epic `dcd#119`「子 3」・バッジ 14/17）。全部 closed の epic・task の部分木を除いて値が変わった行 11 件（例: `dcd#119` は除く前 29/32 → 14/17） | 不一致 0 が合格 | `test_w3_count_and_progress`・`test_progress_matches_tree_without_excluded` | 満たす |
| W4 | closed は「closed も表示」のときだけ。全部 closed の epic・task は気配も出さない。「+N closed」を消す | `closed=0` で出る番号に CLOSED **0 件**、open の見失い **0**、重複 **0**。各行の親 = 最も近い open の祖先で、子の並びも `build` の先行順と全件一致。持ち上げ 2 件（`dcd#193` ← `dcd#126` は `dcd#119` の子の先頭、`dcd#240` ← `dcd#233` は `dcd#174` の子の先頭）。画面で注記「親 #126 は closed」「親 #233 は closed」の 2 つが出る（「逸脱の印と注記を表示」のとき）。全部 closed の epic・task 42 件はどこにも出ない。`closed=1` で 657 件が 1 回ずつ（画面の段 3 でも見える 657・重複 0、「完了」「見送り」のバッジ 489 = closed 489）、`liftedFrom` は全部 null。`index.html` に `+${hidden} closed` も `closed: "1"` の link も無い | 0 件が合格 | `test_w4_closed_hidden_and_lifted`・`test_no_trace_when_all_children_excluded`・`test_closed_hint_removed` | 満たす |
| W5 | 絞り込み中は一致した行に至る経路だけを開く | 9 条件すべてで、出る行 = 「一致 ＋ その表示上の祖先」、開く行 = 祖先だけ、`lone.defaultOpen` も期待値どおり。`closed=0`: `label=blocked`（一致 3・出る 5）、`q=#1000`（一致 1・出る 4: `dcd#431` → `dcd#755` → `dcd#952` → `dcd#1000`）、`label=experiment`（21・49）、`label=task`（28・39）、`label=epic`（21・21。**一致が別の一致の祖先でもある行 2**）、`q=validation`（0・0）。`closed=1`: `label=blocked`（3・6）、`q=#126`（1・2）、`label=epic`（26・26、祖先でもある一致 2）。`closed=0` の 4 条件は stub DOM でも見える行と開く行が `view` と一致 | 集合が一致で合格 | `test_w5_filtering`・`test_filter_resets_level_and_rows` | 満たす |
| W6 | 量に耐えるか（記録のみ・方向なし） | `view` 1 回 **0.97 ms**、応答の JSON 372 KB（うち `view` 22 KB）。server 経由の実取得 9.8 秒（GitHub と git の読み取り。cache 中は 0.006 秒）、`closed=2` は 400 | — | — | 記録のみ |
| W7 | 画面の JS の回帰テスト | `openAt <= level` を `<` に変えると `test_levels_open_by_open_at` が落ちる（7 件中 1 件 FAIL）。戻すと progress のテスト 37 件が 0.21 秒で全部通る（node あり、skip 0） | 変異で落ちるのが合格 | `test_progress_page.py` | 満たす |

## 検出力の確認（positive control）

照合のコードが「検出できないだけ」でないことを、`progress_view.py` の写しに変異を入れて確かめた。

| 変異 | 照合の出力 |
|---|---|
| 進捗から除くノードの除外を外す | W3 の `progress` 不一致 11 件 |
| `shown` を常に真にする（closed も出す） | W4 の CLOSED 混入 489 件、W1 の集合が不一致 |
| 根の task を `epics` に入れる | W1 の集合が不一致 |
| 持ち上げた行を兄弟の末尾に回す | W4 の子の並びの不一致 2 件 |
| 絞り込み中は `lone.defaultOpen` を常に真にする | W5 の `lone.defaultOpen` が 3 条件で不一致 |
| 見送った親の配下を見送りに数えない | **実データでは検出しない**（closed で見送りの、open の子孫を持つノードが 0 件）。fixture のテスト 2 件が落ちるので、この規則は fixture でだけ確かめている |

## 未確認

- 実ブラウザで 4 ボタンと行のクリックを目で確かめること（§6 W2）。この環境にブラウザが無い。stub DOM は `toggle` の非同期配送と `<select>` の値の扱いだけを実ブラウザに合わせたもので、CSS・レイアウト・実際のクリックの配送は見ていない
