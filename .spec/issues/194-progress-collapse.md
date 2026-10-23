# Issue #194: spec: 進捗一覧の階層の開閉と closed の隠し方

## メタ情報

- 作成日: 2026-10-24
- ステータス: completed
- 親: task #193 / epic #192
- 実装: #195（feature）、判定: #196（validation）
- 前の仕様: `.spec/issues/176-progress-server.md`（§5 の「epic を展開、CLOSED の子は『+N closed』に畳む」を本仕様で置き換える）

## 1. 目的

進捗一覧（`scripts/progress/index.html`）は、open な epic・task を最初から全部開いて描く
（`nodeEl` の `folder(num, s, filtering(opt) || (n.kind !== "issue" && n.state === "OPEN"))`、`index.html:149`）。
下流 delta-clip-dev（issue 639 件）では一度に並びすぎて読めない。最初は最上位だけを閉じた状態で出し、
行ごと・一括で開けるようにし、closed は「closed も表示」を入れたときだけ出す。

## 2. 前提（ユーザー確定事項。epic #192 の原文）

- 「epic->task->issueの階層的な展開をできるようにして欲しい。多すぎて見え何。」（2026-10-23）
- 初期表示は「epic だけ並べる」（2026-10-23、選択肢から）
- 親の無い task・issue は「epic と『親なし』1 行」（2026-10-23、選択肢から）
- 「closeしたものは出さないでね。」（2026-10-23）
- 「全部closeされたepicやtaskは特別な処理をしない限り気配もないようにしておけ。」（2026-10-23）
- 閲覧のみ（epic #170 から継続）
- epic #170 から継続: 常時読み込みのファイルに記述を足さない。テストは 1 秒未満で、ネットワークも git も使わない（`.spec/issues/176-progress-server.md` §2）

## 3. 未確定の解消（task #193 の `## 未確定` の 2 行）

### 3-1. closed の親の下に open の子があるとき → 子を「最も近い open の祖先」の下へ持ち上げる

「closed も表示」が切れているとき、closed のノードは**行として出さない**。その open の子孫は、
**最も近い open の祖先の子として**出す（祖先が全部 closed なら根に置き、§4-1 の根の振り分けに従う）。

| 案 | 前提との関係 | 採否 |
|---|---|---|
| A. いまの形（closed の親を「完了」付きで経路として出す。`visible()` の `if (!opt.closed && n.state === "CLOSED") return kidVisible;`、`index.html:135`） | 「closeしたものは出さないでね」に反する（closed の行が出る） | 不採用 |
| B. open の子も一緒に隠す | open を見失う。前提は open を隠せとは言っていない | 不採用 |
| **C. 持ち上げる** | closed の行は出ない。open は全部どこかに出る | **採用** |

持ち上げた子には、`progress_tree.build` が注記「親 #N は closed」を付ける（`notes`。既定は非表示で、
「逸脱の印と注記を表示」を入れたときだけ出る。§176 §3-1 の注記と同じ扱い）。既定では closed の親の気配は出ない。

fixture での例: #81（open）は #80（closed の task）の子 → epic #1 の直下に出る。#111 は #110（closed）の子 → epic #1 の直下。

### 3-2. 閉じた行の件数・進捗バッジに closed を数えるか → 件数は数えない。進捗バッジは既存の定義のまま

| 表示 | closed を数えるか | 実体 |
|---|---|---|
| **子の件数**（閉じた行の summary に出す新しい数） | **数えない。** その行を開いたときに実際に出る子の行の数と同じ値にする（§4-1 の `count`）。「closed も表示」を入れたら closed も数える | `progress_view.view` の `count = len(children)` |
| **進捗バッジ**（既存の `progress`。`完了 / （全数 − 見送り）`） | **既存の定義のまま**（closed の葉を「完了」に数える） | `progress_tree.progress`（`progress_tree.py:168-178`）。変更しない |

理由: 進捗バッジは「この open の行がどこまで済んだか」という**その行自身の量**で、closed の行を出すものではない。
closed を数えないと完了が常に 0 になり、goal の「既存の `progress` バッジ」の意味が消える。
一方、子の件数は「開くと何行出るか」の案内なので、出ない closed を数えると「開いたのに件数より少ない」という
closed の気配になる。全部 closed の epic・task はそもそも行にならないので、そのバッジも件数も出ない。

★ **この結果、件数とバッジの分母は一致しない。** fixture の #2 は `closed=False` で「子 4」、バッジは `1/5 見送り 1`（closed の #15 を完了、#16 を見送りに数える）。バッジは「済んだ量」として closed の葉を数えるので、そこから closed の子があったことは読める。これは goal の「既存の `progress` バッジ」を保つための意図した差である。#196 は実データでこの差が出る行の例を 1 つ以上コメントに示し、ユーザーが判断できるようにする。

## 4. 入力 → 処理 → 出力

| 段 | 内容 | 実体 |
|---|---|---|
| 木 | 既存のまま（`progress_tree.build`）。注記「親 #N は closed」（§3-1）を足す | `scripts/progress/progress_tree.py` |
| 表示の木（新規） | 木と絞り込み（closed・label・q）から、出す行・各行の子・件数・既定の開閉・一括で開く段を決める。**純関数** | `scripts/progress/progress_view.py`（新規）の `view(tree, closed, label, q)` |
| API | `GET /api/tree.json?closed=1&label=<名>&q=<文字列>` が既存の値に `view` を足して返す（キャッシュは木だけを持ち、`view` は要求ごとに作る） | `scripts/progress/server.py` の `do_GET` |
| 画面 | `view` をそのまま描く。絞り込みの判定・closed の判定を JS に持たない（`visible`・`matches`・`filtering` を消す） | `scripts/progress/index.html` |

判定の規則を Python 側に置くのは、テストを既存どおり `scripts/tests/test_progress_*.py`（unittest、ネットワーク・git・ブラウザ不要）で書くため。
JS に残すのは「`view` を DOM にする」「一括の段を覚える」「利用者が開け閉めした行を覚える」だけ。

### 4-1. `view(tree, closed, label, q)` の規則

戻り値: `{"epics": [item], "lone": {"count": N, "items": [item], "defaultOpen": bool}}`。
`item = {"number", "children": [item], "count", "defaultOpen", "openAt"}`。

| 項目 | 規則 | 決める値 |
|---|---|---|
| 出すノード | `closed` が偽なら state が OPEN のノードだけ。真なら全部 | `shown(n)` |
| 親子 | 出すノードの親 = 木の上で最も近い「出す」祖先（§3-1 の持ち上げ）。`closed` が真なら木の親そのもの | `item.children` |
| 根の振り分け | 親が無い（持ち上げで根になったものを含む）ノードのうち、kind が epic → `epics`、task・issue → `lone.items`。順は木の `roots` の順（持ち上げた子は元の親の位置） | `epics`・`lone.items` |
| 絞り込み | **判定は「出すノード」の中だけで行う**（`closed=False` なら closed のノードは一致しない。例: `q="#80"` は 0 行）。`label` は `labels` に含まれる、`q` は `#番号` なら番号一致・それ以外はタイトルの部分一致（小文字化。現 `matches`、`index.html:123-129` と同じ）。絞り込み中は、一致したノードと、その祖先（表示の木の上の）だけを出す | `match(n)` |
| 件数 | `count = len(children)`（その行を開いたら出る行の数） | `item.count`、`lone.count = len(lone.items)` |
| 既定の開閉 | 絞り込みが無いとき: **全部 false**。絞り込み中: 子孫に一致があるときだけ true（一致した行そのものは、子孫に一致が無ければ閉じたまま） | `item.defaultOpen`、`lone.defaultOpen` |
| 一括で開く段 | `openAt`: epic → 1、task → 2、子を持つ issue → 3。`lone` は 1 | `item.openAt` |

全部 closed の epic・task（自身が closed で、open の子孫も無い）は、`closed` が偽なら `view` のどこにも番号が現れない
（行・件数・`lone.count` のどれにも入らない）。

### 4-2. 画面

| 要素 | 規則 | 実体 |
|---|---|---|
| 初期表示 | `view.epics` の各行と、閉じた「親なし (N)」1 行（N = `lone.count`。0 なら出さない）。すべて閉じている | `render()` |
| 行 | 子を持つ行は `<details>`（クリックで開閉）。summary に既存のバッジ（`badges()`）と、新しく「子 N」（`item.count`） | `nodeEl()` |
| 一括 | フィルタの並びの上に 4 つのボタン「epic まで開く」（段 1）「task まで開く」（段 2）「すべて開く」（段 3）「すべて閉じる」（段 0）。押すと段を覚え、利用者が個別に開け閉めした記録（`toggled`）を消して描き直す | `level` 変数 |
| 開閉の決め方 | `toggled` にあればそれ、無ければ `defaultOpen || openAt <= level` | `folder()` |
| 絞り込みを変えたとき | `level = 0` にし `toggled` を消す（一致した行に至る経路だけが開く） | `writeParams()` |
| closed | 既存の「closed も表示」（`index.html:52`）を残す。入れたら `closed=1` で `view` を取り直す。「+N closed」（`index.html:152-157`）は消す | |
| 要約の 3 群 | 変更しない（もともと OPEN だけ） | |

入力のたびの取り直しは既存の 150 ms の待ち（`writeParams`）を通す。サーバーは木をキャッシュから読むので GitHub は呼ばない。

## 5. 制約

- 閲覧のみ（GET だけ。§176 §6 と同じ）。1 ファイル 300 行以内
- 常時読み込みのファイル（rules・CLAUDE.md・スキル本文）に記述を足さない
- テストは `scripts/tests/test_progress_*.py`（fixture は `progress_fixture.py`）。ネットワーク・git・ブラウザ不要で、追加分を含めて合計 1 秒未満
- `index.html` はデータを `textContent` でだけ描く（V6 を保つ）

## 6. 判定（validation #196。実データは omron-sinicx/delta-clip-dev。結果は #196 のコメントに項目ごとの「満たす／満たさない」で残す）

goal の項目と、それを決める値・確かめ方の対応。

| # | goal の項目 | 決める値（コード） | テスト（fixture） | 実データ（delta-clip-dev） |
|---|---|---|---|---|
| W1 | 最初はすべて閉じ、親を持たない epic と閉じた「親なし (N)」1 行だけ | `view(...)` の `epics`・`lone`、`defaultOpen`（絞り込み無し） | `closed=False` で `epics` の番号集合が {1, 72}、`lone.items` が {40, 41, 60, 70, 71, 74, 100}（循環を切って根になった側。#73 は closed なので入らない）。全 `defaultOpen` が false | `epics` の番号集合が、**`view` を使わず**木の生データ（各 issue の `parent`・`state`・ラベル）から別に計算した「OPEN の epic のうち、`parent` を辿って OPEN の祖先が 1 つも無いもの」の集合と一致。初期に出る行数（`len(epics) + 1`）と、出ている全行の `defaultOpen` が false であることを記録 |
| W2 | 行ごとの開閉と一括の 4 ボタン | `item.openAt`、`index.html` の `level` | epic の `openAt`=1、task=2、子を持つ issue=3、`lone` は段 1 で開く。`index.html` に 4 つのボタンの文言がある | 段 0〜3 のそれぞれで開く `<details>` の数（`openAt <= level` の数）を記録。段 3 で全ノードが出る（出る番号の数 = OPEN の件数） |
| W3 | 閉じた行に子の件数と進捗 | `item.count`、`node.progress` | `count` が `len(children)` と一致し、closed の子を数えない（#2 は `closed=False` で 4、`closed=True` で 6）。`progress` は既存の値のまま | 全 item の `count` が、**`view` を使わず**生データから数えた「その行の子孫のうち、間に OPEN を挟まない OPEN のノードの数」と一致。子を持つ全行に `progress` がある。件数とバッジの分母が違う行の例を 1 つ以上示す（§3-2） |
| W4 | closed は「closed も表示」のときだけ。全部 closed の epic・task は気配も出さない。「+N closed」を消す | `shown(n)`、持ち上げ（§3-1） | `closed=False` の `view` に出る番号はすべて OPEN。#81・#111 が epic #1 の直下。#80・#110 は出ない。`closed=True` では全ノードが出る。`index.html` に `closed` の案内の文言が無い。**fixture に足すもの**: 全部 closed の task（子も全部 closed）を open の epic の下に 1 つ、全部 closed の根の epic を 1 つ、closed の根の epic の下の open の issue を 1 つ。前 2 つの番号は `closed=False` の `view` のどこにも（`count`・`lone.count` を含め）現れず、最後の 1 つは `lone.items` に入る | `closed=False` で出る番号に CLOSED が 0 件。OPEN が全件出る（見失いが 0）。持ち上げが起きた件数を記録 |
| W5 | 絞り込み中は一致した行に至る経路だけを開く | `match(n)`、`defaultOpen` | `q="#770"` で、出る行が #1 → #756 → #770 だけ、#1・#756 が開き #770 は（子が無いので）葉。`label="blocked"` で #92 に至る経路だけ | 実在のラベル 1 つと `#番号` 1 つで、出る行が「一致 + その祖先」と一致し、開いているのが祖先だけ |
| W6 | （量に耐えるか） | `view` の所要時間 | — | **記録のみ（方向なし。合否を付けない）**: 639 件で `view` 1 回の所要時間と JSON の大きさ。W1〜W5 の判定には使わない |

既存の V1〜V8（§176 §7）はそのまま通ること（回帰）。

## 7. 範囲外

- 書き込み（close・ラベル・コメント）
- 開閉の状態を URL に持つこと（絞り込みは従来どおり URL に持つ。開閉は持たない）
- 要約の 3 群の変更

## 変更履歴

- 2026-10-24: 初版
- 2026-10-24: auto-reviewer の指摘 5 点を反映（全部 closed の fixture、件数とバッジの差の明記、実データの照合を `view` と独立に、W6 は記録のみ・W1 の期待値を集合で、絞り込みの判定範囲）
