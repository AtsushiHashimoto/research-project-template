# Issue #203: validation: 進捗一覧のカード型・メタ情報・判定の見直し

- 実施日: 2026-10-24 JST
- ステータス: in-progress（W5 の上流での close の実走だけが残っている。ユーザーの許可待ち。実走したら結果はこのファイルの W5 の行と冒頭の判定に書き足す）
- 対象のコード: main = a5b24b6（feature #202、PR #205 マージ後）
- 仕様: `.spec/issues/201-progress-cards.md` §9（W1〜W8。W8 は記録のみ）
- 実データ: omron-sinicx/delta-clip-dev（閲覧のみ）。**issue 660 件**（open 168・closed 492）、PR 348 件、ref 304 本（基準 `refs/remotes/origin/main` に無いもの 150 本）。
  取得の時刻 `now` = 2026-10-24 18:53:38 JST。以下の件数はこの `now` での値
- 以下、**下流の issue 番号は `dcd#N`**（delta-clip-dev の #N）と書く。この repo の #N と取り違えないため
- 測定スクリプトと出力は #203 のコメントに全文（一回きりの測定。恒常的なテストは増やしていない）。このファイルは判定の記録

## 判定: 判定する 7 項目（W8 は記録のみ）のうち、満たす 3（W2・W4・W6）、一部が未了か誤判定 4（W1・W3・W5・W7）

- W1・W7: 機械的な検査と stub DOM の範囲では満たす。**実ブラウザでの目視が未実施**
- W3: 規則の実装は独立の値と一致する。**goal の文言に対しては `dcd#70` の 1 件を誤判定**（原因は仕様の結び付け方。下記）
- W5: 下流で close の経路（server の検査と GitHub での再確認）まで満たす。**上流での close の実走が未実施**（ユーザーの許可待ち）

独立の値は `progress_tree.build`・`progress_work` を使わず、取得した生データ（issue・PR・ref・基準に無い ref の集合）から別のコードで数えた。
**独立でないもの**: ブランチ名から番号を読む規則は、仕様 §3-1 の規則を別の正規表現で書き直したもので、意味は同じ（規則そのものの誤りは検出できない）。
基準に無い ref の集合（`git for-each-ref --no-merged`）と tip の時刻（committerdate）は、実装の `progress_git.read_unmerged`・`read_refs` で読んだ値を共有している。
画面は実ブラウザが無い（chromium・playwright なし）ので、`page.js` を `scripts/tests/progress_page_harness.js` の stub DOM の上で node（`TZ=UTC`）で動かし、実データの `view` を入れて読んだ。
stub DOM の chip とメタ行の期待値は、実装の木（`build` の出力）から組んでいる（描画が判定どおりかの確認で、判定そのものの照合は上の独立の値が担う）。

| # | goal の項目 | 実データの結果 | 基準 | fixture のテスト | 判定 |
|---|---|---|---|---|---|
| W1 | カード型・テキスト圧（K1〜K8。仕様 §5-1 の表） | 段 3 で描いたカード **161 枚**（= `closed=0` で出る行 161）。K1（子を持つカードの最初の子が `SUMMARY`、子のカードは summary の外、summary の中は `head`・`meta`（・`confirm`）だけ）の違反 **0**。K4（chip の文言が固定の集合の中で、決まった順）の違反 **0**、chip の並びが node の判定から組んだ期待値と不一致 **0**（`closed=1` の 660 枚でも 0。chip「完了扱い」7 枚・「完了」463 枚・「見送り」29 枚）。K2（本文を取らない）は issue と PR の query に `body` が無いことを `test_k2_no_body` が検査。K3・K5〜K8（見出し行の折り返し、chip とメタ行の字の大きさと色、タイトルの太さ、カードの背景・角丸・余白）は CSS の静的な検査（`Static.*`）が通る | 違反 0 が合格 | `test_k1_card_structure`・`test_k4_chips_fixed_and_ordered`・`Static.*` | 機械的な検査の範囲で満たす。**実ブラウザでの目視（K3・K5〜K8 の見た目、375px 幅で横スクロールが出ないこと）と画面写しは未実施** |
| W2 | メタ情報 5 種 | カード 161 枚のメタ行が、独立に組んだ文字列（JST の `MM-DD`、年違いは `YYYY-MM-DD`、PR は番号の最大の 1 本と `+k`）と **不一致 0**（`closed=1` の 660 枚でも 0）。PR の結び付き: ブランチ名で **343 / 348 本**（外れる 5 本は番号を持たないブランチ名）、node ごとの `prs` の番号の並びの不一致 **0**。`lastCommit` の不一致 **0**（ブランチを持つ open 22 件）。task の `steps` の不一致 **0**。epic の段の帯（5 つの四角）の不一致 `closed=0` で **0**・`closed=1` で **0** | 不一致 0 が合格 | `test_w2_*`・`test_k6_meta_dates_in_jst` | 満たす |
| W3 | 作業中 | 実装 **4 件** = 独立 4 件（差 0）: `dcd#751`（tip 13.5 日前）・`dcd#859`（3.5 日）・`dcd#885`（3.4 日）・`dcd#1006`（0.1 日）。4 件とも根拠は「基準に無い新しい tip」。仕様 §4-1 が外れるべきと挙げた 10 件（`dcd#119`・`#386`・`#486`・`#496`・`#250`・`#352`・`#361`・`#373`・`#515`・`#537`）と `dcd#1008` は全部 `working = false`。`workingBelow` 5 件 = 独立 5 件。`summary.working` も一致。**結び付かない open の PR 1 本: PR `dcd#118`**（head `chore/template-skills-migration`、本文 `Refs #70`、2026-08-01 から更新なし）。`dcd#70` は open なので、goal の文言（open の PR があるもの）では作業中になるはずが、仕様 §3-1 の結び付け（head のブランチ名と closing keyword だけ）では拾えない | 差 0 が合格 | `test_w3_rules_and_boundaries` 他 | **規則の実装は満たす。goal の文言に対しては `dcd#70` の 1 件を誤判定**（警告の帯 `#banner` に「issue に結び付かない open の PR: #118」と出るので黙っては外れない）。原因は実装の誤りではなく、仕様 §3-1 が「PR 本文の `Refs #N` で結び付ける案」を不採用にしたこと |
| W4 | 完了扱いで隠す | 実装 **7 件** = 独立 7 件: `dcd#476`・`#587`・`#608`・`#609`・`#893`・`#908`・`#924`（再帰にしても同じ 7 件）。`closed=0` の `view` に完了扱い **0 件**、closed **0 件**、出ない open（gone でないもの）**0 件**、重複 0。`closed=1` で 660 件が 1 回ずつ | 0 件が合格 | `Hidden.test_w4_completed_like`・`ViewRules.*` | 満たす |
| W5 | 異常と close | 異常 **6 件** = 独立 6 件: `dcd#469`・`#566`・`#567`・`#590`・`#777`・`#809`。close ボタンが付くカードはこの 6 枚だけ（`closed=0` の他の 155 枚、`closed=1` の他の 654 枚は 0）。**下流で server を実取得で立て、Python の HTTP client で叩いた**（`gh issue close` だけは実行せず、argv を記録して成功を返す runner に差し替え）: Origin 無し・`null`・ポート違い・独自ヘッダ無し・`text/plain` は 403、Host が外は 403、`charset=utf-8` 付きは通って GitHub の確認へ進む。GitHub の確認: `dcd#431`（子 8 件）・PR の番号 `dcd#1007`（NOT_FOUND）・closed の `dcd#1000`・epic/task でない `dcd#1006` は全部 409。`dcd#469` は 200 で、記録した argv は `gh issue close 469 --repo omron-sinicx/delta-clip-dev --reason not planned` の 1 本だけ。実行後に `gh issue view` で `dcd#469` が OPEN（更新 2026-09-15 のまま）であることを確かめた。他の path の POST・`GET /api/close` は 405 | 期待のコードと argv が合格 | `test_progress_close.py`・`test_progress_server.py`・`test_w5_close_needs_second_press` | **下流: close の経路の判定は満たす。close の実走は前提（閲覧のみ）により下流では行わず「検証不能（上流で代替）」。上流での実走は未実施（ユーザーの許可待ち）**。`gh issue close` が失敗したときの 502 の経路は fixture でだけ確かめている |
| W6 | 30日動きなし | 実装 **112 件** = 独立 112 件（task #200 の時点の値と同じ）。chip「30日動きなし」が出るカード 110 枚（差の 2 件 `dcd#476`・`#587` は完了扱いで隠れている。`closed=1` では 112 枚）。完了扱いでない動きなしが `closed=0` の `view` に出ない件数 **0** | 0 件が合格 | `Hidden.test_w6_stale_marks_only` | 満たす |
| W7 | 一括の手応え（B1〜B3。仕様 §5-3） | 実データで段 0〜3 を押すと、押した段のボタンだけ `aria-pressed="true"`。`#bulk-state` の N は、別のコードで数えた「見えている開いた `<details>`」と一致: **0 / 15 / 37 / 38**（文言「すべて閉じている」「epic まで · 開いている 15 行」…）。同じボタンの再押下で「 · 再適用」。段 1 で task を手で 1 つ開けると全部 `"false"` と「· 手で変えた 1 行」。絞り込み中（`q=#1006`）は全部 `"false"` と「一致への経路だけ開いている · 開いている 3 行」 | 一致が合格 | `test_b1_b2_pressed_and_state`・`test_b3_reapply` | stub DOM の範囲で満たす。**実ブラウザでの目視は未実施** |
| W8 | 取得時間（記録のみ・方向なし） | issue 7.67 秒（7 ページ）と PR 2.29 秒（4 ページ、78 KB）を並行に取得、git の読み取り 0.04 秒、`build` 0.013 秒、`view` 0.004 秒、合計 **8.24 秒**（比べる値: 仕様 §3-2 が記録した変更前の issue の取得 8.5 秒。今回は測り直していない）。server 経由の初回 GET 8.09 秒・cache 中 0.009 秒、応答 537 KB | — | — | 記録のみ |

**実データが通らなかった経路**: 作業中の 4 件はすべて「基準に無い新しい tip」で決まり、open の PR による作業中は 0 件（open の PR は `dcd#118` の 1 本だけで結び付かない）、fork の PR は 0 本。
tip がちょうど 14 日に近い ref も無い（最も近いもので 13.46 日）。これらの経路と境界は fixture でだけ確かめている。

## feature の段からの申し送り（UI の指摘）の判定

| 指摘 | 実際の挙動（実データ） | 仕様 | goal |
|---|---|---|---|
| 絞り込み中の「すべて閉じる」で経路が閉じない | `q=#1006` で「すべて閉じる」を押すと、開いた 3 行はそのまま、文言は「一致への経路だけ開いている · 開いている 3 行 · 再適用」、押された印は全部 `"false"` | `.spec/issues/194-progress-collapse.md` §4-2「既定の開閉」（絞り込み中は経路の行が既定で開き、段は開く行を足すだけ）どおり | 「押したこと・今どこまで開いているか」は文言で分かるので満たす。ただし**ボタンの名前と結果が食い違う**（閉じると書いてあるのに閉じない）。194 の規則の変更になるので、この task の範囲外としてユーザーの判断に回す |
| 警告の帯（`#banner`）の色分け | 下流では `#banner` に「issue に結び付かない open の PR: #118」が常に出る。`#banner` は 1 種類の色（`var(--warn)` の枠と背景、`scripts/progress/index.html:21`）で、取得失敗と同じ赤で出る | 仕様は帯の色を決めていない（§3-1 は「帯に出す」だけ） | K1〜K8 は満たす。ただし**情報の行がエラーと同じ赤で常に出る**ので、テキスト圧の点では逆向き。仕様で決めていない箇所なのでユーザーの判断に回す |
| 段の帯（5 つの四角）の凡例 | 5 つの四角の意味は、hover の `title`・`aria-label`（「survey 0/0, spec 1/1, …」）と直後の 1 語（最初の未完の段）でだけ分かる。「表示の規則」にも段の帯の説明が無い | §5-2 どおり（凡例は仕様に無い） | 「どこまで閉じたかを出す」は満たす。見ただけで四角と段の対応が分からない点は、仕様に無い追加としてユーザーの判断に回す |

## 検出力の確認（positive control）

仕様 §9 の 7 つの変異を、`scripts/progress`・`scripts/tests` の写し（worktree の外）に 1 つずつ入れて progress のテスト 65 件を走らせた。

| 変異 | 落ちたテスト |
|---|---|
| `WORKING_DAYS` を 15 に | `test_w2_prs_and_unlinked`・`test_w3_rules_and_boundaries` |
| `<=` を `<` に（ちょうど 14 日） | `test_w3_rules_and_boundaries` |
| `STALE_DAYS` を 31 に | `test_k4_chips_fixed_and_ordered`・`test_w2_prs_and_unlinked`・`test_w6_stale_marks_only` |
| `completedLike` の `>= 1` を `>= 0` に | 5 件 FAIL・13 件 error（`test_w4_completed_like` 他） |
| Origin の比較を外す | `Checks.test_headers` |
| epic の帯の集計で `shown` を外す | `test_w2_epic_steps_count_shown_tasks_only` |
| B1 で `aria-pressed` を全部 true | `test_b1_b2_pressed_and_state`・`test_b3_reapply` |
| （/review が追加）「新しい tip」から「基準に無い」の条件を外す | **fixture では 1 件も落ちない（65 件全部通る）**。fixture に「基準に含まれ、14 日以内で、open の PR が無い」ブランチが無いため。実データでは下の表のとおり検出する |

実データの照合のコードの検出力。上の 4 行は実装に変異を入れた木を同じ照合にかけた結果、最後の行は照合の側で規則を変えて実装と比べた結果:

| 変異 | 照合の出力 |
|---|---|
| `WORKING_DAYS` を 13 に | 作業中の差 1 件（`dcd#751`、tip 13.5 日前） |
| `completedLike` から「子が 1 件以上」を外す | 完了扱いの差 6 件（異常の 6 件）、`closed=0` で出ない open 6 件 |
| 「新しい tip」から「基準に無い」の条件を外す | 作業中の差 1 件（`dcd#1008`。main の先端と同じ tip のブランチだけを持つ） |
| `STALE_DAYS` を 31 に | **実データでは検出しない**（更新が 30〜31 日前の open が 0 件）。fixture のテスト 3 件が落ちるので、境界は fixture でだけ確かめている |
| （照合の側）epic の段の帯に隠れた task も数える | 帯が変わる epic 9 件（`dcd#119`・`#174`・`#343`・`#431` 他）。実装の帯はこの 9 件で「出す task だけ」の値と一致した |

## 未確認

- **上流での close の実走**（W5）: 使い捨ての epic を 1 件作り、実ブラウザから close して状態が変わることを確かめる（ブラウザの `fetch` が Origin と独自ヘッダを付けて送ることも、ここで初めて確かめられる）。上流への書き込みなのでユーザーの許可を待っている
- 実ブラウザでの目視と画面写し（W1 の K3・K5〜K8、375px 幅、W7 の 4 ボタン）。この環境にブラウザが無い。stub DOM は CSS・レイアウトを見ず、イベントが親へ伝わらない（`<summary>` の中の close ボタンを押したときにカードが開閉しないこと、Esc が確認行に届くことは、実ブラウザでは確かめていない）
- fixture の不足: 「基準に含まれ、14 日以内で、open の PR が無い」ブランチが無く、その条件を外す変異を fixture が検出しない（実データでは `dcd#1008` で検出する）
