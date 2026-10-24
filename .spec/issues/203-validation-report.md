# Issue #203: validation: 進捗一覧のカード型・メタ情報・判定の見直し

- 実施日: 2026-10-24 JST
- ステータス: in-progress（W5 の上流での close の実走だけが残っている。ユーザーの許可待ち）
- 対象のコード: main = a5b24b6（feature #202、PR #205 マージ後）
- 仕様: `.spec/issues/201-progress-cards.md` §9（W1〜W8。W8 は記録のみ）
- 実データ: omron-sinicx/delta-clip-dev（閲覧のみ）。**issue 660 件**（open 168・closed 492）、PR 348 件、ref 304 本（基準 `refs/remotes/origin/main` に無いもの 150 本）。
  取得の時刻 `now` = 2026-10-24 18:53:38 JST。以下の件数はこの `now` での値
- 以下、**下流の issue 番号は `dcd#N`**（delta-clip-dev の #N）と書く。この repo の #N と取り違えないため
- 測定スクリプトと出力は #203 のコメントに全文（一回きりの測定。恒常的なテストは増やしていない）。このファイルは判定の記録

## 判定: 8 項目のうち 6 項目は満たす。W3 は 1 件を goal の文言どおりに判定できない。W5 の上流での close の実走は未実施

独立の値は `progress_tree.build`・`progress_work` を使わず、取得した生データ（issue・PR・ref・基準に無い ref の集合）から
別のコードで数えた（ブランチ名の読み方も別の正規表現で書いた）。画面は実ブラウザが無い（chromium・playwright なし）ので、
`page.js` を `scripts/tests/progress_page_harness.js` の stub DOM の上で node（`TZ=UTC`）で動かし、実データの `view` を入れて読んだ。

| # | goal の項目 | 実データの結果 | 基準 | fixture のテスト | 判定 |
|---|---|---|---|---|---|
| W1 | カード型・テキスト圧（K1〜K8） | 段 3 で描いたカード **161 枚**（= `closed=0` で出る行 161）。K1 の構造違反 **0**（子を持つカードの最初の子が `SUMMARY`、子のカードは summary の外、summary の中は `head`・`meta`（・`confirm`）だけ）。K4 の chip が固定の集合の外 **0**・順の違反 **0**。K2: issue と PR の query に `body` が無い。K3・K5〜K8 は CSS の静的な検査（`Static`）が通る | 違反 0 が合格 | `test_k1_card_structure`・`test_k4_chips_fixed_and_ordered`・`Static.*` | 規則の機械的な検査の範囲で満たす。**実ブラウザでの目視（K3・K5〜K8 の見た目、375px 幅で横スクロールが出ないこと）は未実施** |
| W2 | メタ情報 5 種 | カード 161 枚のメタ行が、独立に組んだ文字列（JST の `MM-DD`、年違いは `YYYY-MM-DD`、PR は番号の最大の 1 本と `+k`）と **不一致 0**。PR の結び付き: ブランチ名で **343 / 348 本**（外れる 5 本は番号を持たないブランチ名）、node ごとの `prs` の並びの不一致 **0**。`lastCommit` の不一致 **0**（ブランチを持つ open 22 件）。task の `steps` の不一致 **0**。epic の帯の不一致 `closed=0` で **0**・`closed=1` で **0** | 不一致 0 が合格 | `test_w2_*`・`test_k6_meta_dates_in_jst` | 満たす |
| W3 | 作業中 | 実装 **4 件** = 独立 4 件（差 0）: `dcd#751`（tip 13.5 日前）・`dcd#859`（3.5 日）・`dcd#885`（3.4 日）・`dcd#1006`（0.1 日）。4 件とも根拠は「基準に無い新しい tip」で、open の PR によるものは 0。§4-1 の外れるべき 10 件と `dcd#1008` は全部 `working = false`。`workingBelow` 5 件 = 独立 5 件。`summary.working` も一致。**結び付かない open の PR 1 本: PR `dcd#118`**（head `chore/template-skills-migration`、本文 `Refs #70`、2026-08-01 から更新なし）。`dcd#70` は open なので、goal の文言（open の PR があるもの）では作業中になるはずが、§3-1 の結び付け（ブランチ名だけ）では拾えない | 差 0 が合格 | `test_w3_rules_and_boundaries` 他 | **規則の実装は満たす。goal の文言に対しては `dcd#70` の 1 件を誤判定**（帯に「issue に結び付かない open の PR: #118」と出るので黙っては外れない）。原因は実装の誤りではなく、仕様 §3-1 が本文の `Refs #N`（案 B）を読まないと決めたこと |
| W4 | 完了扱いで隠す | 実装 **7 件** = 独立 7 件: `dcd#476`・`#587`・`#608`・`#609`・`#893`・`#908`・`#924`（再帰にしても同じ 7 件）。`closed=0` の `view` に完了扱い **0 件**、closed **0 件**、出ない open（gone でないもの）**0 件**、重複 0。`closed=1` で 660 件が 1 回ずつ | 0 件が合格 | `Hidden.test_w4_completed_like`・`ViewRules.*` | 満たす |
| W5 | 異常と close | 異常 **6 件** = 独立 6 件: `dcd#469`・`#566`・`#567`・`#590`・`#777`・`#809`。close ボタンが付くカードはこの 6 枚だけ（他の 155 枚は 0）。**下流で server を実取得で立て、HTTP で叩いた**（`gh issue close` だけは実行せず argv を記録する runner に差し替え）: Origin 無し・`null`・ポート違い・独自ヘッダ無し・`text/plain` は 403、Host が外は 403、`charset=utf-8` 付きは通って GitHub の確認へ進む。GitHub の確認: `dcd#431`（子 8 件）・PR の番号 `dcd#1007`（NOT_FOUND）・closed の `dcd#1000`・epic/task でない `dcd#1006` は全部 409。`dcd#469` は 200 で、記録した argv は `gh issue close 469 --repo omron-sinicx/delta-clip-dev --reason not planned` の 1 本だけ（`dcd#469` は実行後も OPEN）。他の path の POST・`GET /api/close` は 405 | 期待のコードと argv が合格 | `test_progress_close.py`・`test_progress_server.py`・`test_w5_close_needs_second_press` | **下流: close の経路の判定は満たす。close の実走は前提（閲覧のみ）により下流では行わず「検証不能（上流で代替）」。上流での実走は未実施（ユーザーの許可待ち）** |
| W6 | 30日動きなし | 実装 **112 件** = 独立 112 件（task #200 の時点の値と同じ）。chip「30日動きなし」が出るカード 110 枚（差の 2 件 `dcd#476`・`#587` は完了扱いで隠れている）。完了扱いでない動きなしが `closed=0` の `view` に出ない件数 **0** | 0 件が合格 | `Hidden.test_w6_stale_marks_only` | 満たす |
| W7 | 一括の手応え（B1〜B3） | 実データで段 0〜3 を押すと、押した段のボタンだけ `aria-pressed="true"`。`#bulk-state` の N は、別のコードで数えた「見えている開いた `<details>`」と一致: **0 / 15 / 37 / 38**（文言「すべて閉じている」「epic まで · 開いている 15 行」…）。同じボタンの再押下で「 · 再適用」。段 1 で task を手で 1 つ開けると全部 `"false"` と「· 手で変えた 1 行」。絞り込み中（`q=#1006`）は全部 `"false"` と「一致への経路だけ開いている · 開いている 3 行」 | 一致が合格 | `test_b1_b2_pressed_and_state`・`test_b3_reapply` | stub DOM の範囲で満たす。**実ブラウザでの目視は未実施** |
| W8 | 取得時間（記録のみ・方向なし） | issue 7.67 秒（7 ページ）と PR 2.29 秒（4 ページ、78 KB）を並行に取得、git の読み取り 0.04 秒、`build` 0.013 秒、`view` 0.004 秒、合計 **8.24 秒**（変更前の issue だけの取得 8.5 秒）。server 経由の初回 GET 8.09 秒・cache 中 0.009 秒、応答 537 KB | — | — | 記録のみ |

## feature の段からの申し送り（UI の指摘）の判定

| 指摘 | 実際の挙動（実データ） | 仕様 | goal |
|---|---|---|---|
| 絞り込み中の「すべて閉じる」で経路が閉じない | `q=#1006` で「すべて閉じる」を押すと、開いた 3 行はそのまま、文言は「一致への経路だけ開いている · 開いている 3 行 · 再適用」、押された印は全部 `"false"` | 194 §3（絞り込み中は経路の `defaultOpen` が真で、段はそれに足すだけ）どおり | 「押したこと・今どこまで開いているか」は文言で分かるので満たす。ただし**ボタンの名前と結果が食い違う**（閉じると書いてあるのに閉じない）。194 の規則の変更になるので、この task の範囲外としてユーザーの判断に回す |
| 帯の色分け | 下流では帯に「issue に結び付かない open の PR: #118」が常に出る。帯は 1 種類の色（`#banner` は `var(--warn)` の枠と背景）で、取得失敗と同じ赤で出る | 仕様は帯の色を決めていない（§3-1 は「帯に出す」だけ） | K1〜K8 は満たす。ただし**情報の行がエラーと同じ赤で常に出る**ので、テキスト圧の点では逆向き。仕様で決めていない箇所なのでユーザーの判断に回す |
| 段の帯の凡例 | 5 つの四角の意味は、hover の `title`・`aria-label`（「survey 0/0, spec 1/1, …」）と直後の 1 語（最初の未完の段）でだけ分かる。「表示の規則」にも段の帯の説明が無い | §5-2 どおり（凡例は仕様に無い） | 「どこまで閉じたかを出す」は満たす。見ただけで四角と段の対応が分からない点は、仕様に無い追加としてユーザーの判断に回す |

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

実データの照合のコード側の検出力（実装に変異を入れた木を、同じ照合にかけた）:

| 変異 | 照合の出力 |
|---|---|
| `WORKING_DAYS` を 13 に | 作業中の差 1 件（`dcd#751`、tip 13.5 日前） |
| `completedLike` から「子が 1 件以上」を外す | 完了扱いの差 6 件（異常の 6 件）、`closed=0` で出ない open 6 件 |
| epic の帯に隠れた task も数える | 帯が変わる epic 9 件（`dcd#119`・`#174`・`#343`・`#431` 他）。実装の帯はこの 9 件で独立の値（出す task だけ）と一致した |
| `STALE_DAYS` を 31 に | **実データでは検出しない**（更新が 30〜31 日前の open が 0 件）。fixture のテスト 3 件が落ちるので、境界は fixture でだけ確かめている |

## 未確認

- **上流での close の実走**（W5）: 使い捨ての epic を 1 件作り、ブラウザ（または同じ要求）から close して状態が変わることを確かめる。上流への書き込みなのでユーザーの許可を待っている
- 実ブラウザでの目視（W1 の K3・K5〜K8、375px 幅、W7 の 4 ボタン）。この環境にブラウザが無い。stub DOM は CSS・レイアウト・実際のクリックの配送を見ていない
