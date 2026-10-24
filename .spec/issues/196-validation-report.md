# Issue #196: validation: 進捗一覧の階層の開閉と closed の隠し方

- 実施日: 2026-10-24 JST
- 対象のコード: main = 077d619（feature #195、PR #198 マージ後）
- 仕様: `.spec/issues/194-progress-collapse.md` §6（W1〜W7）
- 実データ: omron-sinicx/delta-clip-dev（閲覧のみ）。**issue 657 件**（task 作成時の 639 件から増えた）、open 168 件、closed 489 件
- 測定スクリプトと出力は #196 のコメントに全文（一回きりの測定。恒常的なテストは増やしていない）

## 判定: 6 項目とも満たす（W2 の実ブラウザでの目視だけ未確認）

独立の値は `view` を使わず、`progress_tree.build` の `nodes`（`parent`・`children`・`state`・`kind`）から別のコードで数えた。
画面は実ブラウザが無い（chromium・playwright なし）ので、`index.html` の `<script>` を `scripts/tests/progress_page_harness.js` の stub DOM の上で node で動かし、実データの `view` を入れて数えた。

| # | goal の項目 | 実データの結果 | 基準 | 判定 |
|---|---|---|---|---|
| W1 | 最初はすべて閉じ、親を持たない epic と「親なし (N)」1 行だけ | `epics` 14 件・`lone` 42 件が独立の集合と一致（差 0）。全 item と `lone` の `defaultOpen` が false。初期の行数 **15**（epic 14 ＋「親なし (42)」） | 差 0・開いている行 0 が合格 | 満たす |
| W2 | 行ごとの開閉と一括の 4 ボタン | `openAt` が epic 1・task 2・issue 3 で全件一致。開く `<details>` の数は段 0 / 1 / 2 / 3 で **0 / 15 / 37 / 38**（`openAt <= level` の期待値と一致）、見える行は **14 / 99 / 166 / 168**。段 3 の見える番号 168 = open 168（重複 0）。行を 1 つ開くと見える行 14 → 17、描き直しの後も開いたまま | 期待値と一致・段 3 で open 全件が合格 | 満たす（stub DOM。**実ブラウザでの目視は未確認**） |
| W3 | 閉じた行に子の件数と進捗 | `count` の不一致 **0**、`progress` の不一致 **0**（`closed=0`）、`closed=1` で `node.progress` との不一致 **0**。件数とバッジの分母が違う行 32 件（例: epic #119「子 3」・バッジ 14/17）。全部 closed の epic・task の部分木を除いて値が変わった行 11 件（例: #119 は除く前 29/32 → 14/17） | 不一致 0 が合格 | 満たす |
| W4 | closed は「closed も表示」のときだけ。全部 closed の epic・task は気配も出さない。「+N closed」を消す | `closed=0` で出る番号に CLOSED **0 件**、open の見失い **0**、重複 **0**。各行の親 = 最も近い open の祖先。持ち上げ 2 件（#193 ← #126、#240 ← #233。`liftedFrom` は元の親で closed）。全部 closed の epic・task 42 件はどこにも出ない。`closed=1` で 657 件が 1 回ずつ、`liftedFrom` は全部 null。`index.html` に `+${hidden} closed` も `closed: "1"` の link も無い | 0 件が合格 | 満たす |
| W5 | 絞り込み中は一致した行に至る経路だけを開く | 4 条件すべてで、出る行 = 「一致 ＋ その open の祖先」、開く行 = 祖先だけ（view と stub DOM の両方で一致）: `label=blocked`（一致 3・出る 5）、`q=#1000`（一致 1・出る 4: #431 → #755 → #952 → #1000）、`label=experiment`（一致 21・出る 49）、`q=validation`（一致 0・出る 0） | 集合が一致で合格 | 満たす |
| W6 | 量に耐えるか（記録のみ・方向なし） | `view` 1 回 **0.97 ms**、応答の JSON 372 KB（うち `view` 22 KB）。server 経由の実取得 9.8 秒（GitHub と git の読み取り。cache 中は 0.006 秒）、`closed=2` は 400 | — | 記録のみ |
| W7 | 画面の JS の回帰テスト | `openAt <= level` を `<` に変えると `test_levels_open_by_open_at` が落ちる（7 件中 1 件 FAIL）。戻すと progress のテスト 37 件が 0.21 秒で全部通る（node あり、skip 0） | 変異で落ちるのが合格 | 満たす |

## 検出力の確認（positive control）

照合のコードが「検出できないだけ」でないことを、`progress_view.py` の写しに変異を入れて確かめた。

| 変異 | 照合の出力 |
|---|---|
| 進捗から除くノードの除外を外す | W3 の `progress` 不一致 11 件 |
| `shown` を常に真にする（closed も出す） | W4 の CLOSED 混入 489 件、W1 の集合が不一致 |
| 根の task を `epics` に入れる | W1 の集合が不一致 |

## 未確認

- 実ブラウザで 4 ボタンと行のクリックを目で確かめること（§6 W2）。この環境にブラウザが無い。stub DOM での実行は `toggle` の非同期配送と `<select>` の値の扱いだけを実ブラウザに合わせたもので、CSS・レイアウト・実際のクリックの配送は見ていない
