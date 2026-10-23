# Issue #185: spec: スキルの手順を scripts/flow/ に移植する

## メタ情報

- 作成日: 2026-10-23
- ステータス: reviewed（/review-spec 7 観点を反映した第 2 版）
- 親: task #184 / epic #183
- 移植元: omron-sinicx/delta-clip-dev の `scripts/flow/*.sh`・`scripts/check-discipline*.sh`・`tests/test_{issue,commit,quick}_flow.sh`・`tests/test_task_run.sh`（同 repo の main @ f07fc06）

## 1. 目的

自動実行系スキルの判断を含まない手順を bash に移し、SKILL.md を薄くする（token を減らす）。worktree を task 単位にする。
移した後も、確認画面を除く判断ゲートが働くことを、ゲートを外すと落ちるテストで示す。

用語: **ワーカー** = `/task-run` のメインが issue ごとに起動するサブエージェントで、スクリプトを呼び、実装し、判断を書く役。**停止** = スクリプトが `next_fail`（何が足りないか・書くべき行・再実行コマンドを stdout に出して exit 1）で止まること。`die` はスクリプト自身の異常（引数・gh の失敗）にだけ使う。

## 2. 前提（epic #183 の原文を要約。原文は epic 本文）

| # | 前提 | この仕様での扱い |
|---|---|---|
| P1 | worktree は task 単位 | §3-2 |
| P2 | token とゲート時間を増やさない | SKILL.md の合計を減らす（§7 V3）。重い flow テストは関係時だけ（§6） |
| P3 | PR でマージまで行う | — |
| P4 | 確認画面（task-run 0-5・epic-cycle 1-2・issue-finish の承認）は無し | 移植しない。対のスナップショットブランチ（`pre-task/`・`pre-epic/`）と `--dry-run`・`--no-merge`・`--from`・`--unattended` も移植しない |
| P5 | 研究の規律の関門はスクリプトの検査で戻す | §4 |
| P6 | sub-epic だけ上流へ。他の下流ルールは外す | §3-4。**外すものは上流にコードを残さない**（切り替えの環境変数も作らない） |
| P7 | 区切りの案内は /compact に統一 | §3-5 |
| P8 | 1.5 は spec の issue だけ。実装はワーカー | §4 |

## 3. 構成

### 3-1. 置くもの・変えるもの・消すもの

| パス | 中身 |
|---|---|
| `scripts/flow/lib.sh` | `next`／`next_fail`／`die`／`gh_json`／`handoff_steps`／`task_of`／`realign_branch`／`branch_prefix`（**接頭辞の表の単一情報源**）／共著者の行（定数 1 つ） |
| `scripts/flow/lib-quality.sh` | 種類ごとの品質チェックの範囲。同じ HEAD での再実行の省略（記録に `HEAD`・範囲・`QUALITY_FULL_SCAN` の値を入れ、3 つとも一致したときだけ省く） |
| `scripts/flow/{issue-create,issue-start,issue-branch,issue-finish,commit,task-run,epic-cycle,quick}.sh` | 各スキルの手順 |
| `scripts/check-discipline.sh`・`check-discipline-predicates.sh` | ゲートの述語（§4）。新しいゲートもここに置き、モード名は §4 の表のとおり |
| `.claude/skills/{issue-create,issue-start,issue-branch,issue-finish,commit,commit-only,commit-push,commit-merge,task-run,epic-cycle,task-start}/SKILL.md` | §5 |
| `.claude/skills/task-run/references/worker.md` | ワーカーの起動文・報告の形式・メインの動き（メインがワーカーを起動するときだけ読む） |
| `tests/test_{issue,commit,quick}_flow.sh`・`tests/test_task_run.sh` | 下流から移す。偽の `gh` は **issue ごとに本文・コメント・ラベル・状態・子** を返す形に広げる（§4 のゲートを落とすテストに要る）。`git add -A` を前提にした筋書きは名指しの stage に直す |
| `scripts/read-premises.sh` | sub-epic に対応: 最上位の epic まで辿り、途中の epic すべての前提を出す（子の epic が先）。テストに issue → task → sub-epic → epic の fixture を足す |
| `.claude/rules/template/agent-runtime.md` | 「手順の正はスクリプトの出力（`次にやること`）。SKILL.md は呼び方だけを持つ」を 1 行足す |
| `.claude/rules/template/git-workflow.md` | PR とコミットの issue 参照を `Refs #N` にする（close は `issue-finish.sh` だけが行う。`Closes` で squash すると GitHub が先に閉じ、完了コメントが付かない）。`Closes #N` のコミットは `check merge` が直し方つきで止める |
| `.claude/rules/template/issue-hierarchy.md` | sub-epic（epic の親は epic でもよい。2 段まで。`/epic-cycle` は葉だけ）と、小タスクの親は task（task 単位の worktree を共有するため）を足す。計 5 行以内 |
| `.claude/rules/template/deliverables.md` | §3-5 |
| `scripts/quality-check.sh` | §6。`commit-merge.sh` の検査ブロックを消す |

**消すもの**: `scripts/commit-merge.sh`・`tests/test_commit_merge.sh`（`commit.sh merge` に置き換わる）。後者の検査（lock された worktree の削除 等）は `tests/test_commit_flow.sh` に移す。sync は削除を伝えないので、移行手順（PR 本文と `docs/` の更新履歴）に「下流は 2 ファイルを手で消す」と書く。

**issue-create の呼び出し元**: `/task-start` は `--body-file` 付きで呼ぶ形に直す（無いと `issue-create.sh` が task の作成を止める）。他の呼び出し元（`/issue-gaps`・`/issue-backlog`・`/issue-unblock`・`/review-integrity`・`/template-sync`）は呼び方を表にして確かめ、task を作るものは同じく直す。

### 3-2. task 単位の worktree（P1）

- ブランチ `<prefix>/<TASK>-i<N>`、worktree `worktrees/task<TASK>`。同じ task の issue は 1 本を共有し、issue ごとに squash merge した後 `realign_branch` で origin/main に揃える
- 親が task でない issue（単独の bug・chore）はブランチ `<prefix>/<N>-<slug>`、worktree `worktrees/issue<N>`
- 接頭辞は `lib.sh` の `branch_prefix` だけが持つ（`issue-start/SKILL.md` の表は消す）。`chore` → `chore/` を足す。表に無い種類ラベルは停止（既定の接頭辞に丸めない）。`branch_prefix` の値の集合と `check-discipline-predicates.sh` の `BRANCH_TYPES` が一致することをテストで固定する
- worktree の削除は task の最後の open な子を閉じたときだけ。削除は `scripts/worktree-relative.sh remove`
- 作成直後に `scripts/configure-agent-workflow.sh <worktree>` を呼ぶ
- 同じ worktree で次の issue に手を付けるのは、前の issue のマージが済んでから（`commit.sh merge` は作業ツリーが clean であることを要求する）。`task-run.sh` は 1 issue ずつしか案内しないので、手順どおりなら起きない

### 3-3. 上流の規定に合わせて変えるところ

| 下流の現状 | 上流版 |
|---|---|
| `commit.sh` が `git add -A` | ワーカーが名指しで stage する。`commit.sh` は次の 3 通り: stage 済み → コミット（`git diff --cached --stat` を出す）。何も変更が無く未 push のコミットがある → push だけ。未 stage・未追跡だけ → 停止（一覧と `git add <名前>` の例を出す）。`quick.sh` は上限の検査に使ったファイル名をそのまま stage する |
| 既定ブランチを `origin/HEAD` から検出 | `main` 固定 |
| `git worktree unlock/remove` を直に呼ぶ | `scripts/worktree-relative.sh remove` |
| QA の置き場所 `docs/qa` 固定 | `scripts/qa/qa-dir.sh` |
| 共著者の行がモデル名を固定 | `lib.sh` の定数 `Co-Authored-By: Claude <noreply@anthropic.com>`（環境変数で変えない） |
| コメント中の下流の issue 番号・`.spec` の節・下流のルールファイル名 | 理由を文で書き直す。`epic-cycle.sh` の葉の検査は `issue-hierarchy.md` を指す |

### 3-4. 下流だけのルール（P6）

| 項目 | 上流版 |
|---|---|
| sub-epic | 上流に入れる（§3-1 の `issue-create.sh`・`epic-cycle.sh`・`read-premises.sh`・`issue-hierarchy.md`） |
| goal をコード上の実体で書く（epic 雛形の 1 行） | 消す。epic 雛形は `## 前提（ユーザー確定事項）` 節を含む上流の形に戻す |
| chore 単独 issue の数を epic の判定に引用（`check quick`） | 消す |
| `LEGACY_MAX=485`（古い issue の検査の免除） | 消す（免除しない） |
| `quick.sh` の上限（3 ファイル・50 行） | `readonly` の定数のまま残す |
| 確認画面を前提にした表現（「確認したら」等） | 消す |

下流が残したいものは、下流の差分として下流が持つ（上流に切り替えの口を作らない）。

### 3-5. 区切りの案内（P7）

- 文言は `lib.sh` の `handoff_steps` だけが持つ: 「区切りです。/compact をどうぞ。再開は `bash scripts/flow/<task-run|epic-cycle>.sh <番号>`」。引き継ぎの `### 次の一手` に同じ再開コマンドを書かせる
- `deliverables.md` は文言を写さず `handoff_steps` を指す。「/clear」と「SessionStart フックが読み込む」の 2 行は、フックを登録したときの話として条件付きに直す

## 4. 判断ゲート（P5・P8）

**どのゲートも、外すと落ちるテストを持ち、止まったときの出力（何が足りないか・書くべき行の原文・再実行コマンドの 3 点）をテストで grep する。** 1 回の停止で、落ちた行をすべて引用する（1 行ずつ止めない）。

| ゲート（中身） | モード（`check-discipline.sh`） | 検査 |
|---|---|---|
| goal の空欄（上流 G1・G2） | `goal <TASK>` | task 本文に `## 目標の状態`（前方一致）。その節に `成功条件` と `negative の意味` の行があり、値が空でない。値は `^\s*-\s*\**(成功条件\|negative の意味)\**\s*[:：]\s*(.+)$` の `(.+)` で、空白だけ・`<…>` だけ（雛形のまま）・`TBD`・`未定` は空とみなす |
| goal の実質（上流 G1b・G3・G4。成功条件が 1 文の合否の述語になる・未確定に言及する語を削っても何を作り何を測るかが残る・解釈が 1 つ） | `goal <TASK>` | task の**最新の** `## goal ゲート` コメントが、本文の最終編集（GraphQL `lastEditedAt`、無ければ作成時刻）より新しく、`^- (G1b\|G3\|G4): PASS — .+$` の 3 行を持つ。判定はワーカーではなく、ワーカーが起動する `verification` のサブエージェントが書く（スクリプトの停止文が起動文と判定の読み方を出す） |
| 未確定の担当（上流 G5〜G7b） | `goal <TASK>` | `## 未確定`（前方一致）の各行が `→`（または `->`）の後に種類ラベルか `#N` を持つ（装飾と後ろの補足は無視）。ラベルならその種類の子がある。`#N` ならこの task の子。担当に `out-of-date`・`user-action` が無い。節が無い・空なら続行 |
| 未確定の行を消して逃げない | `goal <TASK>` | 初回の `goal` が PASS したとき、スクリプトが task に `## 未確定（記録）` コメントを書く（項目名の一覧。同じ内容は 1 回だけ）。以後、記録にある項目名が本文の `## 未確定` に無ければ停止 |
| 再照合（上流 0-2b・Step 6） | `goal <TASK>`（task-run の段 0 と各 issue の後） | 担当が**すべて** closed の未確定行は、`解消済み（→ #N, <path>` か `解消不能（理由[:：]\s*\S` に書き換わっていなければ停止。`<path>` は空白か `）` か ` §` の手前まで。`git cat-file -e origin/main:<path>` が通り、`#N` は closed |
| 仕様レビュー（上流 1.5。spec の issue だけ） | `issue`（下流どおり） | `.spec/issues/N-*.md` と `N-auto-decisions.md`。判断ログの停止条件の行が `該当なし`（S1〜S8 に該当していたら停止） |
| 前提の受け渡し | — | auto-reviewer と仕様整合の起動を案内する文に `bash scripts/read-premises.sh <TASK>` の出力を貼る手順がある（テストで出力を grep） |
| 品質チェック（上流 4-1） | `issue-finish.sh`（下流どおり） | 終了コード |
| 仕様整合（上流 4-2） | `merge <N> <種類> [TASK]` | PR 本文の `## 仕様整合` 節（次の `## ` まで）に ❌ が無い。`goal 書き換え: なし` の行がある。種類が experiment か validation なら、節に `positive control:`・`matched-engineering:`・`格付け:` の 3 行があり、格付けが `unverified-negative` なら停止（triage していない negative をマージしない）。検証は `verification` のサブエージェントが行い、ワーカーが PR 本文に貼る |
| /review | `merge`（下流どおり） | PR 本文の `## /review 結果` が空でない |
| task の判定の形 | `verdict-task <TASK>` | task を閉じる前に、最新の `## 判定` コメントに `^結果: (positive\|negative\|未達成)$` の行があり、成功条件を 1 項目ずつ引用している |
| 全部 negative（上流 KI-D11: 全 task が negative なら、まず検出力・実装を疑う） | `verdict <EPIC>` | 閉じた task が 1 件以上あり、その `結果:` がすべて `negative` なら、epic の `## 判定` に空でない `## 全部 negative の確認` 節（positive control を再確認した記述）を求める |

止まった理由は**スクリプトが** task にコメントする（ゲートの中身・足りないもの・JST の時刻。直前のコメントと同じ内容なら書かない）。

## 5. SKILL.md

- 各 SKILL.md は呼び方だけを持ち、50 行以内。手順・判断の読み方は、スクリプトがその段で出す文に置く（その段に来たときだけ読まれる）
- `task-run` のワーカー起動文・報告の形式は `task-run/references/worker.md`（メインが起動時だけ読む）。§7 V3 の合計に含める
- frontmatter（`name`・`description`・`metadata:` と `  harness: shared`）と `agent-runtime.md` の前置き

## 6. 品質ゲート（P2）

- flow のテストは `quality-check.sh` の `changed_any` で、次が変わったときだけ走る: `scripts/flow/`・`scripts/check-discipline`・`scripts/worktree-relative.sh`・`scripts/lib/shared-store.sh`・`scripts/qa/`・`scripts/setup-worktree.sh`・`scripts/handoff.sh`・`scripts/read-premises.sh`・`scripts/configure-agent-workflow.sh`・`scripts/template-contribute-detect.sh`・`scripts/quality-check.sh`・`tests/test_(issue|commit|quick)_flow.sh`・`tests/test_task_run.sh`・`tests/test_pipefail_grep_q.sh`・§3-1 の SKILL.md と `references/`・`.claude/rules/template/(issue-hierarchy|deliverables|git-workflow|agent-runtime).md`。`QUALITY_FULL_SCAN=1` では常に走る
- 範囲の一覧の漏れを防ぐため、`scripts/flow/*.sh` が `bash`・`.` で呼ぶ `scripts/` のファイルがすべて上の範囲に入っていることをテストで確かめる
- 各テストの先頭で `unset BASH_ENV ENV`（実測: bash 1 回の起動 275 ms → 14 ms。4 本合計 417 s → 70 s）

## 7. 判定（validation #187）

| # | 確かめること | 方法 | epic #183 の完了条件 |
|---|---|---|---|
| V1 | §4 の各ゲートが働く | ゲートごとに外す変異を 1 つ以上入れ、flow テストが落ちる。変異の一覧と結果を #187 に記録 | 2 |
| V2 | 既存の上流テストと agent-skills の検査が通る | `python3 scripts/agent-skills.py` でリンクを作ってから `QUALITY_FULL_SCAN=1 bash scripts/quality-check.sh` | 1 |
| V3 | SKILL.md の大きさ | §3-1 の SKILL.md と `references/` の合計を、**bytes（`wc -c`）と文字（`wc -m`）の両方で**、移植前（上流 a5e7558: 対象 10 個で 97,268 bytes・57,193 文字。task-start を足した値も測る）と比べる。↓ 小さいほど良い | 3 |
| V4 | ゲート時間 | 3 通りを同じ時間帯に 2 回ずつ測り、値を記録する: (a) flow に関係しない変更、(b) flow に関係する変更、(c) `QUALITY_FULL_SCAN=1`。移植前の上流でも (a)(c) を測る | 3 |
| V5 | task 単位の worktree で 1 周回る | `tests/test_issue_flow.sh` の 1 周の筋書き（task → spec → feature → validation → close）が上流で通る | 1 |

## 8. 範囲外

- 確認画面と、それと対のもの（P4）
- 下流への sync（下流の issue で行う）

## 変更履歴

- 2026-10-23: 初版
- 2026-10-23: /review-spec 7 観点を反映。全部 negative の検査が発火しない問題を、task の判定の形（`結果:` 行）を決めて直した。前提の受け渡し、`/task-start` の呼び方、sub-epic での前提の読み取り、未確定の行の削除の検出、`Closes` の扱い、名指しの stage の 3 通り、ゲートの受理形式（正規表現）、停止出力の要件、V3 の単位、V4 の 3 通り、`changed_any` の範囲を足した。下流向けの切り替え（環境変数・`local.sh`）は P6 に反するため削除。G1b・G3・G4 の判定はワーカーの自己申告をやめ `verification` のサブエージェントが書く形にした
