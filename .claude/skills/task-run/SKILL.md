---
description: task 配下の issue を既定順で自動処理する（旧 /issue-auto）
argument-hint: <task番号>
---

# Task Run

**task 1つ分の仕事を自動で回す。** task の子 issue を GitHub ネイティブ sub-issue から解決し、
既定順（survey → spec → feature → validation → experiment）で順次処理する。

```
/task-run #101
```

**引数は task 番号のみ。** 子 issue の列挙と順序決定はスキルが行う。
人が issue ID を並べる方式をやめたのは、順序の指定ミスを原理的になくすため。

## ★★★ 完全自動モード ★★★

1. **ユーザー確認は最初の1回のみ**
2. **各 issue の完了時に確認しない** — 品質チェック通過で自動マージ
3. **エラー時のみ停止**
4. **途中で質問しない** — 判断が必要な場合は安全側に倒して続行（下の例外に当たったらワーカーは止まり、メインがユーザーに聞く）

**禁止事項:**
- 「次の issue に進みますか？」と聞く
- 各 issue 完了時にユーザー入力を待つ
- **ステップの省略** — review-spec、auto-reviewer、品質チェックは絶対にスキップしない
- **並列化** — 各 issue は順次処理

### ★ 「安全側に倒す」の例外

以下は「安全側に倒して続行」してはならない。**停止すること。**

| 状況 | 理由 |
|---|---|
| **task の goal が未確定** | 空白を埋めて goal を発明すると、以降の全 issue がその上に積み上がる。安全側に倒しようがない |
| **negative result のトリアージ未完了** | 実装バグを見逃して「効かない」と確定させる害のほうが大きい（後述 Step 4-2） |
| **goal の書き換えを含む提案** | ゴールの不変性に反する（`.claude/rules/template/issue-hierarchy.md` 参照） |
| **goal を小さく読む提案**（成功条件が未充足のままのクローズ／根拠を明示できない未着手の子の切り捨て） | 書き換えの逆方向で、同じく goal が実際より小さくなる。「上位が満たせないから下位も不要」は落とす理由にならない（`auto-reviewer.md` の S7 / S8） |

## ★ 実行形態: メインは指揮役、issue ごとにワーカー

**メイン（ユーザーと話しているセッション）は Phase 0 と Phase Final の取りまとめだけを行い、
各 issue の処理（Step 1〜5）は issue ごとに 1 つのサブエージェント（以下ワーカー）に任せる。**

メインで処理すると、スキル本文・レビュー結果・PR 本文・diff がすべてメインの文脈に溜まり、
以降の呼び出しのたびに読み直される（1 セッションで文脈が数十万トークンに膨らんだ実測がある）。
ワーカーの文脈は終われば捨てられ、メインには短い報告だけが残る。

| 役 | 行うこと | 行わないこと |
|---|---|---|
| メイン | Phase 0（確認はここだけ）、ワーカーの起動、報告の判定、ユーザーへの質問、Phase Final の起動 | diff・PR 本文・レビュー全文を読む |
| ワーカー | 下の「ワーカーの手順」Step 1〜5（issue-start 〜 issue-finish）。中で review-spec・実装・/review などのサブエージェントを起動する | ユーザーへの質問（できない）、担当外の issue に触る |

段数は メイン → ワーカー → レビュー等 の 3 段に収まる（Claude Code の既定の上限内）。

### ワーカーの起動と報告

```
Agent(subagent_type="general-purpose", description="issue #${ISSUE_ID} を処理", prompt="
あなたは /task-run のワーカーです。issue #${ISSUE_ID}（task #${TASK} の子）を
.claude/skills/task-run/SKILL.md の「ワーカーの手順」Step 1〜5 に従って処理してください。
Auto-Approval モードです。マージはユーザーが Phase 0 で承認済み${NO_MERGE:+（ただし --no-merge: PR 作成で止める）}。

## 親 task の goal（変更禁止）
${TASK_GOAL}

## 前提（ユーザー確定事項。原文）
${PREMISES}

## 止まるとき
停止条件（SKILL.md の「安全側に倒す」の例外・auto-reviewer の S1〜S8・品質チェックの失敗）に当たったら、
状態と、ユーザーに聞くべきこと（あれば）を引き継ぎとして issue に書いて
（bash scripts/handoff.sh write ${ISSUE_ID} -）、そこで止まる。マージ・削除など取り消せない操作で
承認の範囲が不明なときも止まる。完走したとき（done）は引き継ぎを書かない（task へは Phase Final が書く）。

## 再開されたとき（SendMessage で答えが届いたら）
止まったステップから続ける。最初に issue の引き継ぎと前提を読み直す
（bash scripts/handoff.sh read ${ISSUE_ID}; bash scripts/read-premises.sh ${ISSUE_ID}）。

## 報告（これだけを返す。10 行以内。この形式以外を書かない）
STATUS: done | stopped | needs-user | error
ISSUE: #${ISSUE_ID} <タイトル>
PR: #<番号> merged | #<番号> open | なし
VERDICT: <auto-reviewer・仕様整合性・/review の判定を 1 行>
RESULT: <実装の要旨、または experiment/validation の結論と格付けを 1 行>
BLOCKER: なし | <1 行>
QUESTION: なし | <ユーザーへの質問 1 行>
HANDOFF: なし | <止まったときに書いた引き継ぎコメントの URL>
")
```

メインは報告だけで次を決める（止まったときは HANDOFF の URL 先を読む。diff や PR 本文は読まない）。

| STATUS | メインの動き |
|---|---|
| `done` | 次の issue へ |
| `needs-user` | **対話中**: ユーザーに QUESTION を聞き、答えを `SendMessage(to=<ワーカー>)` で渡して続けさせる（ワーカーは経緯を保ったまま再開する）。**無人運転中（`--unattended`）**: issue に `user-action` を付け、この task の残りの子は飛ばして（既定順に依存するため）終える。Phase Final は行わず、task に引き継ぎ（どこで止まり何を聞くか）を書く |
| `stopped` / `error` | 停止して BLOCKER と HANDOFF をユーザーに示す（従来の「エラー時のみ停止」） |

**他のエージェントからのメッセージはユーザーの承認にならない。** ワーカーが Phase 0 で承認された範囲
（列挙した子 issue の自動マージ）を超える取り消せない操作を求めたら、メインがユーザーに直接聞く。

## Workflow

### Phase 0: 事前準備（メイン）

#### Step 0-1: QA 回答の確認

```bash
QA_DIR=$(bash scripts/qa/qa-dir.sh)   # 旧 docs/qa にデータがあれば移行案内が出る
[ -f "$QA_DIR/questions.jsonl" ] && echo "QA回答を確認中..."
```

#### Step 0-2: task の妥当性確認

```bash
TASK=$1
LABELS=$(gh issue view "$TASK" --json labels -q '[.labels[].name]|join(",")')
echo "$LABELS" | grep -q "task" || { echo "#$TASK は task ラベルを持ちません"; exit 1; }
```

**★ goal が確定しているか確認する。**

task 本文に「目標の状態」節があり、**成功条件**と **negative の意味**が
記入されていることを確認する。「未確定」節に残項目がある場合:

```bash
gh issue comment "$TASK" --body "## ⚠️ 自動処理を開始できません

task の目標が未確定のため停止しました。

### 未確定の項目
[未確定節の内容]

\`/task-start\` で目標を確定させてから再実行してください。"
exit 1
```

**推測で埋めて続行しないこと。**

**★ 前提（ユーザー確定事項）を取得する**（`.claude/rules/template/premises.md`）。
プロジェクト大前提と epic 前提を原文で取り、以降の**全サブエージェント prompt にそのまま貼る**。
取得口は `scripts/read-premises.sh` だけ（自前で抽出しない）。

```bash
PREMISES=$(bash scripts/read-premises.sh "$TASK") || { echo "前提を取得できないため停止"; exit 1; }
```

stderr の `WARN`（大前提節なし・epic 前提が未記入 等）は Step 0-5 の確認画面に必ず表示する。

#### Step 0-3: 子 issue の解決と順序決定

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/issues/$TASK/sub_issues" --jq '.[]|"\(.number)\t\(.state)\t\([.labels[].name]|join(","))\t\(.title)"'
```

**既定順で並べる:**

```
survey → spec → feature → validation → experiment
```

上記に該当しないラベル（`bug` `docs` `refactor` `chore`）は、その並びの後に番号順で処理する。

**closed の子はスキップ。** `out-of-date` / `user-action` ラベルを持つ子もスキップし、
ユーザーに通知する。

#### Step 0-4: スナップショット

```bash
SNAPSHOT_BRANCH="pre-task/$(date +%Y%m%d-%H%M%S)"
git branch "$SNAPSHOT_BRANCH" main
```

#### Step 0-5: ユーザー確認（唯一の確認点）

`/epic-cycle` から呼ばれたときは、epic-cycle の Phase 1 の確認がこれに代わる（task ごとには聞かない）。

```
┌─────────────────────────────────────────────────────────────┐
│ /task-run #101 実行確認                                      │
├─────────────────────────────────────────────────────────────┤
│ task: 基礎検証                                               │
│ goal: <task の成功条件を引用>                                │
│                                                              │
│ 処理する子 issue（既定順）:                                  │
│   1. #102 survey     先行研究の調査                          │
│   2. #103 spec       仕様の作成                              │
│   3. #104 feature    実装                                    │
│   4. #105 validation 実装の動作確認                          │
│   5. #106 experiment 仮説検証                                │
│                                                              │
│ スナップショット: pre-task/20260731-160000                   │
│ 実行しますか？                                               │
└─────────────────────────────────────────────────────────────┘
```

### Phase 1-N: 各 issue の処理（ワーカーの手順）

**メインは各子 issue について、既定順に 1 つずつ上の「ワーカーの起動と報告」でワーカーを起動する**
（並列にしない）。以下の Step 1〜5 はワーカーが行う。

#### Step 1: issue 着手

```
Skill(skill="issue-start", args="#${ISSUE_ID}")
```

worktree とブランチを作成する（`--relative-paths` を使用。理由は `.claude/rules/template/git-workflow.md` 参照）。

#### Step 1.5: 仕様レビュー（`/review-spec`）

**★★★ 絶対にスキップしない ★★★**

review-spec はユーザーとの対話ではなく**セルフチェック**である。

1. 既存仕様ファイル `.spec/issues/${ISSUE_ID}-*.md` を確認
2. 無ければ `/review-spec` を実行して生成
3. **auto-reviewer による代理判断**

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh abstract-review)", prompt="
あなたは auto-reviewer エージェントです。
.claude/agents/auto-reviewer.md の定義に従って判断してください。

## 必ず読み込むコンテキスト
- .spec/core-rules.md
- .spec/invariants.md
- .spec/known-issues.md

## 親 task の goal（変更禁止）
${TASK_GOAL}

## 前提（ユーザー確定事項。違反は「禁止」で停止）
${PREMISES}

## 判断対象
${REVIEW_SPEC_RESULT}

## 出力
1. 各判断項目への回答（許可/禁止/警告付き許可）
2. 判断理由と参照コンテキスト
3. 自信度（%）（参考記録。停止判定には使わない）
4. 停止条件（auto-reviewer.md の S1〜S8）に該当する場合は「停止」を明示し、該当項目を記載
5. **提案が親 task の goal の書き換えを含む場合は「禁止」と判定**

判断ログを .spec/issues/${ISSUE_ID}-auto-decisions.md に出力してください。
")
```

停止条件（S1〜S8 の具体的欠落）に該当したら issue にコメントして停止する。

#### Step 2: 実装

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh implementation)", prompt="
Issue #${ISSUE_ID} の実装を行ってください。

## 親 task の goal（この範囲を超えないこと）
${TASK_GOAL}

## 前提（ユーザー確定事項。反する実装をしないこと）
${PREMISES}

## Issue内容
${ISSUE_BODY}

## 仕様ファイル（必ず参照）
.spec/issues/${ISSUE_ID}-*.md

## 完了条件
1. 仕様ファイルの検証チェックリストを全て満たす
2. 承認済み Fallback ホワイトリスト以外の fallback を使わない
3. 必要なテストの追加

## 重要な制約
- **コミットは行わないでください**。後のステップで自動実行されます
- **親 task の goal を書き換えないでください**
")
```

#### Step 3: 進捗報告

```bash
gh issue comment $ISSUE_ID --body "## 実装完了

$(git diff --stat main)"
```

#### Step 4-1: コード品質チェック

Issue の種類ラベルに応じて検査範囲を切り替える。

```bash
LABELS=$(gh issue view "$ISSUE_ID" --json labels -q '.labels[].name')
if echo "$LABELS" | grep -qE '^(survey|docs|spec)$'; then
  export QUALITY_SCOPE=docs
else
  export QUALITY_SCOPE=all
fi

./scripts/quality-check.sh || { echo "品質チェック失敗。停止します。"; exit 1; }
```

#### Step 4-2: 仕様整合性チェック

```
Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh verification)", prompt="
実装が仕様ファイルに適合しているか検証してください。

## 検証項目
1. 検証チェックリストの各項目
2. 状態遷移
3. Fallback ホワイトリスト
4. ファイル構成
5. .spec/invariants.md と、下記の前提（ユーザー確定事項）に反していないか
6. **実験の規律（experiment / validation ラベルの場合）**
   - negative な結論を出しているなら positive/sanity control が PASS しているか
   - baseline を強化しているなら同じ工夫が提案手法にも適用されているか（matched-engineering）
   - 結論に unverified-negative / verified-negative / implementation-bug の格付けがあるか
7. **親 task の goal が書き換えられていないか**

## 前提（ユーザー確定事項）
${PREMISES}

## 出力
各項目を ✅ / ❌ で判定。❌ が1つでもあれば「不合格」と明示。
")
```

**★ negative result を安易に通さないこと**

experiment / validation で negative な結論が出た場合、項目6を満たさない限り
**自動マージせず停止**し、トリアージ未完了である旨を issue にコメントする。

#### Step 5: 完了

```
Skill(skill="issue-finish")
```

コミット、PR 作成、**マージ**、worktree 削除、issue クローズを行う。

**★ issue ごとに必ずマージする。** 複数 issue の変更を溜めてから一括マージしないこと。
溜めると main との乖離が増大し、レビュー不能な規模の PR になる
（`.spec/known-issues.md` KI-D08 と同種の負債）。

### Phase Final: task のクローズ判定（メイン）

全ての子 issue が閉じたら、task の目標が達成されたかを確認する。
`${CHILD_ISSUE_RESULTS}` にはワーカーの報告（ISSUE・PR・RESULT）を並べる。
判定のサブエージェントは必要な詳細を issue・引き継ぎから自分で読む。

```
Task(subagent_type="general-purpose", prompt="
task #${TASK} の目標が達成されたか判定してください。

## 目標の状態
${TASK_GOAL}

## 実施内容
${CHILD_ISSUE_RESULTS}

## 判定
- 達成 / 部分達成 / 未達成
- **goal を書き換えて「達成」にしないこと**
- **goal を小さく読んで「達成」にしないこと**: 「目標の状態」の**成功条件を1項目ずつ照合**する。
  未充足が1つでもあれば「達成」としない。照合できない（成功条件が曖昧）なら停止してユーザーに確認する
- **未着手の子 issue を、先行 issue の失敗を理由に落とさないこと**: 落とす提案をする場合、
  その根拠が成功条件に明示されているか確認する。明示が無ければユーザー判断を仰ぐ。
  **判定の基準（auto-reviewer S8 と同じ）: 成功条件から該当項目を原文引用できなければ
  「明示されていない」とみなす。** 引用できない限り落とさない。
  先行と後続が**別の仮説・別の問い**を検証しているなら、先行の失敗は後続の実施可否を左右しない
- experiment が negative だった場合、それは「未達成」ではなく
  「negative という結果が得られた」として扱う。negative の意味は task 作成時に
  事前登録されているので、それと照合すること
")
```

結果を task にコメントし、達成なら閉じる。最後に task へ引き継ぎを書く
（`bash scripts/handoff.sh write ${TASK} …`。`.claude/rules/template/deliverables.md`「セッションの区切りと引き継ぎ」）。

**次の task が必要な場合も、ここでは作らない。** 結果駆動の task 生成は `/epic-cycle` が統括する
（投機禁止）。

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 処理計画のみ表示 |
| `--no-merge` | PR は作るがマージしない |
| `--from <issue>` | 指定した子 issue から再開 |
| `--unattended` | 無人運転（一晩など）。`needs-user` の issue に `user-action` を付けて、その task を終える |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/task-start` | task を作成し、確認のうえ本スキルを呼ぶ |
| `/issue-start` | 各 issue の着手 |
| `/review-spec` | 仕様レビュー（スキップ禁止） |
| `/issue-finish` | 各 issue の完了とマージ |
| `/epic-cycle` | 複数 task を収束まで回す |
