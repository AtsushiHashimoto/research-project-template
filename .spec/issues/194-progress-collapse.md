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

用語: **消えるノード** = state が CLOSED で、OPEN の子孫を 1 つも持たないノード（全部 closed の epic・task とその配下、closed の葉）。
**closed の経路** = state が CLOSED で、OPEN の子孫を持つノード。

### 3-1. closed の親の下に open の子があるとき → 子を「最も近い open の祖先」の下へ持ち上げる

「closed も表示」が切れているとき、closed のノードは**行として出さない**。その open の子孫は、
**最も近い open の祖先の子として**、closed のノードがあった位置に差し込んで出す（祖先が全部 closed なら根に置き、§4-1 の根の振り分けに従う）。

| 案 | 前提との関係 | 採否 |
|---|---|---|
| A. いまの形（closed の親を「完了」付きで経路として出す。`visible()` の `if (!opt.closed && n.state === "CLOSED") return kidVisible;`、`index.html:135`） | 「closeしたものは出さないでね」に反する（closed の行が出る） | 不採用 |
| B. open の子も一緒に隠す | open を見失う。前提は open を隠せとは言っていない | 不採用 |
| **C. 持ち上げる** | closed の行は出ない。open は全部どこかに出る | **採用** |

持ち上げた item には `view` が `liftedFrom`（元の親の番号。持ち上げていなければ `null`）を付ける。画面はこれを
「逸脱の印と注記を表示」を入れたときだけ注記「親 #N は closed」として出す（既定では出さない）。
`closed=1` のときは持ち上げないので `liftedFrom` は常に `null`。`progress_tree.build` は変更しない。

fixture での例: #81（open）は #80（closed の task）の子 → epic #1 の直下、#80 があった位置に出る。#111 は #110（closed）の子 → epic #1 の直下。

### 3-2. 閉じた行の件数・進捗バッジに closed を数えるか

| 表示 | `closed` なし（既定） | `closed=1` | 実体 |
|---|---|---|---|
| **子の件数**（新しく summary に出す「子 N」） | 出る子の行の数（closed は数えない） | 出る子の行の数（closed も数える） | `item.count = len(item.children)` |
| **進捗バッジ**（`完了 / （全数 − 見送り）`） | **子を持つ消えるノード（全部 closed の epic・task 等）を根とする部分木を除いて**数える。closed の葉（子を持たない消えるノード）と、closed の経路の下は数える | 既存の値（`node.progress`）そのまま | `item.progress`（`view` が作る）。`progress_tree.progress`（`progress_tree.py:168-178`）は変更しない |

理由:
- 子の件数は「開くと何行出るか」の案内。出ない closed を数えると、開いたとき件数より少ない＝closed の気配になる。
- 進捗バッジは「この open の行がどこまで済んだか」。closed の葉を完了に数えないと完了が常に 0 になり、goal の「既存の `progress` バッジ」の意味が消える。
  ただし、**全部 closed の epic・task**（消えるノードのうち子を持つもの）の葉まで open の親のバッジに入れると、
  前提「全部closeされたepicやtaskは…気配もないように」に触れる（例: open の epic のバッジの分母が、画面に何も出ない task の分だけ増える）。そこでその部分木だけを除く。
- 結果として、件数とバッジの分母は一致しない（fixture の #2: 「子 4」、バッジ `1/5 見送り 1`。closed の葉 #15 を完了、#16 を見送りに数える）。
  これは closed の issue を「済んだ量」として数える意図した差で、全部 closed の task・epic の気配ではない。

## 4. 入力 → 処理 → 出力

| 段 | 内容 | 実体 |
|---|---|---|
| 木 | 既存のまま（`progress_tree.build`）。変更しない | `scripts/progress/progress_tree.py` |
| 表示の木（新規） | 木と絞り込みから、出す行・各行の子・件数・進捗・既定の開閉・一括で開く段を決める。**純関数**。入力の木を書き換えない | `scripts/progress/progress_view.py`（新規）の `view(tree, closed, label, q)` |
| API | `GET /api/tree.json?closed=1&label=<名>&q=<文字列>` が既存の値に `view` を足して返す。キャッシュは木だけを持ち、`view` は要求ごとに作る | `scripts/progress/server.py` の `do_GET` |
| 画面 | `view` をそのまま描く。絞り込み・closed の判定を JS に持たない（`visible`・`matches`・`filtering` と「+N closed」を消す） | `scripts/progress/index.html` |

依存の向き: `progress_view` は `build` の戻り値（dict）だけを受け取り、`progress_tree`・`server`・`progress_gh` を import しない。`server.py` が `progress_view` を import する。
判定の規則を Python 側に置くのは、テストを既存どおり unittest（ネットワーク・git・ブラウザ不要）で書くため。
JS に残すのは「`view` を DOM にする」「一括の段を覚える」「利用者が開け閉めした行を覚える」「古い応答を捨てる」だけ。

### 4-1. query の受け方（`server.py`）

| 引数 | 受け付ける値 | それ以外 |
|---|---|---|
| `closed` | 省略・`0` → 偽、`1` → 真 | **400**（黙って偽に倒さない） |
| `label` | 省略・空 → 絞り込み無し。任意の文字列（未知のラベルは一致 0 件） | 2 回以上渡されたら 400 |
| `q` | 省略・空（前後の空白を除いて）→ 絞り込み無し。200 文字まで | 201 文字以上、または 2 回以上なら 400 |
| `refresh` | 既存どおり（`refresh=1` かつヘッダ `X-Progress-Refresh: 1` のときだけ取り直す）。絞り込みの引数と同時に渡せる | 既存どおり |

400 の本文は既存の 502 と同じく `{"error": "<理由>"}`。Host 検査（`do_GET` の先頭）は path の振り分けより前のまま。

### 4-2. `view(tree, closed, label, q)` の規則

戻り値: `{"query": {"closed", "label", "q"}, "epics": [item], "lone": {"count", "items": [item], "defaultOpen"}}`。
`item = {"number", "children": [item], "count", "progress", "defaultOpen", "openAt", "liftedFrom"}`。
事後条件: 出てくる番号はすべて `tree["nodes"]` にあり、各番号は高々 1 回現れる。

| 項目 | 規則 | 決める値 |
|---|---|---|
| 出すノード | `closed` が偽なら state が OPEN のノードだけ。真なら全部 | `shown(n)` |
| 親子と並び | 木（`build` の `children` の順。循環は `build` が切った後）を先行順に辿り、出さないノードを「その出す子孫の列」で再帰的に置き換える。これで各ノードの親は「最も近い出す祖先」になり、並びは一意に決まる | `item.children` |
| 根の振り分け | 親が無い（持ち上げで根になったものを含む）ノードのうち、kind が epic → `epics`、task・issue → `lone.items`。順は `tree["roots"]` の順に上の置き換えを当てたもの | `epics`・`lone.items` |
| 絞り込み（一致） | **判定は出すノードの中だけ**（`closed` が偽なら closed は一致しない。例: `q="#80"` は 0 行）。`label` は `labels` に含まれる。`q` は小文字化して前後の空白を除き、固定の regex `^#(\d{1,9})$` に合えば番号一致、合わなければタイトルの部分一致（`#abc` もタイトルの部分一致）。利用者の入力を regex にしない | `match(n)` |
| 絞り込み（出す範囲） | 絞り込み中は、一致したノードと、その祖先（表示の木の上の）だけを出す。**一致したノードの子孫は、それ自身が一致しない限り出さない**（一致した行は子孫に一致が無ければ `count = 0` の葉になる） | — |
| 件数 | `count = len(children)` | `item.count`、`lone.count = len(lone.items)` |
| 進捗 | §3-2。`closed` が真なら `node.progress`。偽なら、子を持つ消えるノードを根とする部分木を除いて `progress_tree.progress` と同じ数え方（見送った親の配下は全部見送り）をする。子を持たない item は `null` | `item.progress` |
| 既定の開閉 | 絞り込みが無いとき: **全部 false**（`lone.defaultOpen` も）。絞り込み中: 出す子があるときだけ true（＝一致に至る経路）。`lone.defaultOpen` は絞り込み中で `lone.items` が空でないとき true | `item.defaultOpen`、`lone.defaultOpen` |
| 一括で開く段 | `openAt`: epic → 1、task → 2、issue → 3。`lone` は 1 | `item.openAt` |
| 持ち上げ | §3-1 | `item.liftedFrom` |

### 4-3. 画面（`index.html`）

| 要素 | 規則 | 実体 |
|---|---|---|
| 初期表示 | `view.epics` の各行と、閉じた「親なし (N)」1 行（N = `lone.count`。0 なら出さない）。すべて閉じている。`epics` も `lone` も空なら、絞り込み中は「一致なし」、そうでなければ「open な issue はありません」を muted で 1 行出す | `render()` |
| 行 | 子を持つ item は `<details>`（クリックで開閉）、子の無い item は葉。summary に既存のバッジ（`badges()`。進捗だけは `item.progress` を使う）と「子 N」（`item.count`） | `nodeEl()` |
| 一括 | フィルタの並びの上に `role="group"`・`aria-label="一括の開閉"` の `<button type="button">` を 4 つ: 「epic まで開く」（段 1）「task まで開く」（段 2）「すべて開く」（段 3）「すべて閉じる」（段 0）。押すと段 `level` を覚え、行の開閉の記録を消して描き直す | `level` 変数 |
| 開閉の決め方 | 行の記録 `toggled`（key は番号と `"lone"`）にあればそれ、無ければ `defaultOpen \|\| openAt <= level` | `folder()` |
| 開閉の記録 | `toggle` イベントで、`d.open` が上の既定と**違うときだけ**記録する（既定・一括で開いた行を利用者の操作として記録しない）。要約の 3 群（key `sum:…`）の記録は別に持ち、一括・絞り込みで消さない | `folder()` |
| 絞り込み・closed を変えたとき | `level = 0` にし、行の記録を消す（一致した行に至る経路だけが開く） | `writeParams()` |
| 取得 | `load()` は URL を `URLSearchParams` で組み立て、いまのフォームの `closed`・`label`・`q` を必ず載せる（「取り直す」の `refresh=1` も同じ URL に足す）。入力のたびの取り直しは既存の 150 ms の待ちを通す。応答の `view.query` がいまのフォームの値と違えば**捨てる**（古い応答が新しい応答の後に届いても描かない） | `load()` |
| 注記 | 「逸脱の印と注記を表示」を入れたとき、`liftedFrom` がある行に注記「親 #N は closed」 | `badges()` |
| 不整合 | `view` の番号が `data.nodes` に無ければ、その行を黙って飛ばさず帯（`showBanner`）に出す | `nodeEl()` |
| ラベルの選択肢 | 既存どおり全ノードのラベル（`fillLabels`）。closed にしか無いラベルを選ぶと「一致なし」になる | |
| closed | 既存の「closed も表示」（`index.html:52`）を残す。「+N closed」の案内（`index.html:152-157`）は消す | |
| 要約の 3 群 | 変更しない（もともと OPEN だけ） | |

描画は `textContent` だけ（V6 を保つ）。

## 5. 制約

- 閲覧のみ（GET だけ。§176 §6 と同じ）。1 ファイル 300 行以内
- 常時読み込みのファイル（rules・CLAUDE.md・スキル本文）に記述を足さない
- テスト: `view` は新規 `scripts/tests/test_progress_view.py`、query と 400 は `test_progress_server.py`、画面の JS は新規 `scripts/tests/test_progress_page.py`（§6 の W7）。fixture は `progress_fixture.py`。ネットワーク・git・ブラウザ不要で、追加分を含めて合計 1 秒未満

## 6. 判定（validation #196。実データは omron-sinicx/delta-clip-dev。結果は #196 のコメントに項目ごとの「満たす／満たさない」で残す）

fixture に足すもの（W4 で使う）: (a) open の epic #1 の下に全部 closed の task #120（子 #121 は closed・COMPLETED）、(b) 全部 closed の根の epic #130（子 #131 は closed）、(c) closed の根の epic #140 の下の open の issue #141。

実データの照合で使う「独立の値」は、`view` を使わず `build` の `nodes`（循環を切った後の `parent`・`children`・`state`・`kind`）から別のコードで数える。

| # | goal の項目 | 決める値（コード） | テスト（fixture） | 実データ（delta-clip-dev） |
|---|---|---|---|---|
| W1 | 最初はすべて閉じ、親を持たない epic と閉じた「親なし (N)」1 行だけ | `view(...)` の `epics`・`lone`、`defaultOpen`（絞り込み無し） | `closed=False` で `epics` の番号集合が {1, 72}、`lone.items` が {40, 41, 60, 70, 71, 74, 100, 141}（#101 は #100 の子。#73・#130・#140 は closed なので入らない）。全 item と `lone` の `defaultOpen` が false | `epics` と `lone.items` の番号集合が、それぞれ独立に数えた「OPEN で、OPEN の祖先を持たない epic」「同じく task・issue」の集合と一致。初期に出る行数（`len(epics) + 1`）を記録 |
| W2 | 行ごとの開閉と一括の 4 ボタン | `item.openAt`、`index.html` の `level`・`folder()` | `openAt` が epic 1・task 2・issue 3。W7 | 段 0〜3 のそれぞれで開く `<details>` の数を記録（W7 と同じ実行を実データの `view` で行う）。段 3 で出る番号の数 = OPEN の件数。ブラウザで 1 回開き、4 ボタンと行のクリックが効くことを目で確かめて記録 |
| W3 | 閉じた行に子の件数と進捗 | `item.count`、`item.progress` | #2 の `count` が `closed=False` で 4、`closed=True` で 6。#2 の `progress` は両方で {1, 5, 1}（closed の葉 #15・#16 は数える）。epic #1 の `progress` は、`closed=False` で `closed=True` の値から #120 の部分木（完了 1・分母 1）を引いた値。`closed=True` では全 item の `progress` が `node.progress` と一致 | 全 item の `count` と `progress` が独立に数えた値と一致。件数とバッジの分母が違う行の例を 1 つ以上コメントに示す（§3-2） |
| W4 | closed は「closed も表示」のときだけ。全部 closed の epic・task は気配も出さない。「+N closed」を消す | `shown(n)`、持ち上げ（§3-1）、§3-2 の進捗 | `closed=False` の `view` に出る番号はすべて OPEN。#81 は #1 の子の列で #80 があった位置に、`liftedFrom` = 80。#111 は `liftedFrom` = 110。#120・#121・#130・#131 は `view` のどこにも現れない（`count`・`lone.count`・`progress` にも寄与しない）。#141 は `lone.items` に入る。`closed=True` では全ノードが 1 回ずつ出て、`liftedFrom` は全部 null。`index.html` に `` `+${hidden} closed` `` と `closed: "1"` の link の組み立てが無い | `closed=False` で出る番号に CLOSED が 0 件。OPEN が全件、1 回ずつ出る（見失い 0）。持ち上げが起きた件数を記録 |
| W5 | 絞り込み中は一致した行に至る経路だけを開く | `match(n)`、`defaultOpen` | `q="#770"`: 出る行が #1 → #756 → #770 だけ、#1・#756 が開き #770 は葉。`label="blocked"`: #1 → #90 → #92 だけ。`q="#2"`: #1 → #2 で、#2 は `count = 0`。`q="#80"`: 0 行。`q="#40"`: `epics` が空、`lone.items` が [#40]、`lone.defaultOpen` が true。`q="#81"`: #1 → #81 | 実在のラベル 1 つと `#番号` 1 つで、出る行が独立に数えた「一致 + その祖先」と一致し、開いているのが祖先だけ |
| W6 | （量に耐えるか） | `view` の所要時間 | — | **記録のみ（方向なし。合否を付けない）**: 639 件で `view` 1 回の所要時間と JSON の大きさ |
| W7 | 画面の JS（W2 の一括・W4 の削除・取得） | `index.html` の `<script>` | `test_progress_page.py`: `index.html` の `<script>` を抜き出し、最小限の DOM の stub を付けて `node` で実行する。fixture の `view` を入れ、段 0〜3 で開く `<details>` の key の集合が `openAt <= level` の期待値と一致。ボタンで行の記録が消え、`sum:` の記録は残る。`view.query` が違う応答を描かない。`load()` の URL に `closed`・`label`・`q` が載る。**`node` が無い環境では SkipTest に理由を書いて明示的に skip する** | #196 で `openAt <= level` を `<` に変えると W7 が落ちることを実測で確かめる |

API（`test_progress_server.py`）: `closed=2`・`q` が 201 文字・`label` が 2 回で 400。`refresh=1&q=#770`（ヘッダ付き）でも絞り込んだ `view` が返る。
`view` の事後条件（番号が `nodes` にあり高々 1 回）と、`view` が入力の木を書き換えないことを `test_progress_view.py` で固定する。
既存の V1〜V8（§176 §7）はそのまま通ること（回帰）。

## 7. 範囲外

- 書き込み（close・ラベル・コメント）
- 開閉の状態を URL に持つこと（絞り込みは従来どおり URL に持つ。開閉は持たない）
- 要約の 3 群の変更

## 変更履歴

- 2026-10-24: 初版
- 2026-10-24: auto-reviewer の指摘 5 点を反映（全部 closed の fixture、件数とバッジの差の明記、実データの照合を `view` と独立に、W6 は記録のみ・W1 の期待値を集合で、絞り込みの判定範囲）
- 2026-10-24: /review 7 観点を反映。進捗バッジから全部 closed の epic・task の部分木を除く（前提「気配もない」との食い違い）。持ち上げの注記を `build` から `view` の `liftedFrom` へ移す。query の検証（400）、`q` の番号判定を固定 regex に、一致したノードの子孫は出さない、並びの一意化、`lone.defaultOpen`、空の表示、古い応答を捨てる、`toggled` の記録の条件と `sum:` の分離、`load()` の URL に絞り込みを載せる、W7（node で JS を実行）を追加
