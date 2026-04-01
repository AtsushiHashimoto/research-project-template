---
description: Automatically process multiple issues in sequence (複数Issueの自動処理)
argument-hint: [issue_ids...]
---

# Issue Auto-Processing

複数のIssueを自動的に順番に処理します。

## ★★★ 重要: 完全自動モード ★★★

**このコマンドは「自動」処理です。以下を厳守してください：**

1. **ユーザー確認は最初の1回のみ** - 処理開始前の確認だけ
2. **各Issueの完了時に確認しない** - 品質チェック通過で自動マージ
3. **エラー時のみ停止** - 品質チェック失敗や重大な問題がある場合のみ
4. **途中で質問しない** - 判断が必要な場合は安全側に倒して続行

**禁止事項:**
- 「次のIssueに進みますか？」と聞く
- 「マージしてよいですか？」と聞く
- 各Issue完了時にユーザー入力を待つ

**Permission Mode の維持:**
- このコマンドは **bypass permissions on** の状態で実行されることを前提とする
- 各Issue処理の開始時に permission mode が bypass permissions であることを確認し、もし accept edits に変わっていたら bypass permissions に戻すこと
- サブエージェント（Agent tool）完了後やSkill呼び出し後に permission mode がリセットされる場合があるため、各ステップ間で注意すること


## Usage

```
/issue/auto 2 3 4        # Issue #2, #3, #4 を順番に処理
/issue/auto 2,3,4        # カンマ区切りも可
/issue/auto --all-open   # 全てのopen Issueを処理（out-of-dateを除く）
```

**注意**: 以下のラベルが付いたIssueは自動的にスキップされます:
- `out-of-date`: 古くなったIssue
- `in-progress`: 作業中のIssue
- `user-action`: ユーザー対応が必要なIssue

## Safety Features

### 1. マージ前スナップショット
```bash
# 処理開始前に main のスナップショットを作成
git branch "pre-auto/$(date +%Y%m%d-%H%M%S)" main
```

いつでもこのブランチに戻れます:
```bash
git checkout pre-auto/YYYYMMDD-HHMMSS
```

### 2. 実行前確認
処理開始前にユーザーに確認:
- 処理対象Issue一覧
- 実行順序（依存関係考慮）
- 自動承認の範囲

### 3. 品質チェック自動評価
各Issue完了時に品質チェックを実施し、問題があれば停止。

## Workflow

### Phase 0: 事前準備

#### Step 0: QA回答の確認

**前回セッションで投げた質問への回答を確認**:

```bash
# docs/qa/answers.jsonl をチェック
if [ -f "docs/qa/questions.jsonl" ]; then
  echo "QA回答を確認中..."
  # /qa/check 相当の処理を実行
fi
```

未確認の回答がある場合：
```
📬 新しいQA回答があります:

### Q001: データフォーマットの選択
- 質問: CSV と JSON どちらが好ましいですか？
- 仮決定: JSON
- 回答: JSON で問題ありません
- 回答者: hashimoto

✅ 仮決定と一致。追加対応不要。

---

### Q002: 認証方式
- 質問: OAuth2 と API Key どちらを使いますか？
- 仮決定: なし（deferred）
- 回答: OAuth2 を使ってください

⚠️ 実装が必要です。関連Issue: #21
```

回答に基づいて作業計画を調整してから、後続のステップに進む。

#### Step 1: 引数解析
   ```bash
   # Issue IDのリストを取得
   ISSUE_IDS="$ARGUMENTS"
   # カンマをスペースに変換
   ISSUE_IDS=$(echo "$ISSUE_IDS" | tr ',' ' ')
   ```

2. **スキップ対象フィルタリング**
   ```bash
   # スキップ対象ラベルが付いたIssueをフィルタリング
   # - in-progress: 既に作業中
   # - out-of-date: 古くなったIssue
   # - user-action: ユーザー対応が必要
   FILTERED_IDS=""
   SKIPPED_IDS=""
   for ID in $ISSUE_IDS; do
     LABELS=$(gh issue view $ID --json labels -q '.labels[].name')
     if echo "$LABELS" | grep -q "in-progress"; then
       SKIPPED_IDS="$SKIPPED_IDS $ID"
       echo "Skip #$ID (in-progress)"
     elif echo "$LABELS" | grep -q "out-of-date"; then
       SKIPPED_IDS="$SKIPPED_IDS $ID"
       echo "Skip #$ID (out-of-date)"
     elif echo "$LABELS" | grep -q "user-action"; then
       SKIPPED_IDS="$SKIPPED_IDS $ID"
       echo "Skip #$ID (user-action) - ユーザー対応が必要"
     else
       FILTERED_IDS="$FILTERED_IDS $ID"
     fi
   done
   ISSUE_IDS="$FILTERED_IDS"
   ```

   スキップされたIssueがある場合、ユーザーに通知:
   ```
   ⚠️ 以下のIssueはスキップされます:
   - #3: 初期仕様 (out-of-date)
   - #5: 認証機能 (in-progress)
   - #7: API統合テスト (user-action) - ユーザー対応が必要

   ラベルを外せば処理対象になります。
   user-action ラベルのIssueはユーザーが完了させてください。
   ```

3. **依存関係の解析**
   ```bash
   # 各Issueの情報を取得
   for ID in $ISSUE_IDS; do
     gh issue view $ID --json title,body,labels
   done
   ```

   Issue本文に `depends on #N` や `blocked by #N` があれば順序を調整。

4. **処理順序の決定**
   - 依存関係がないIssueは番号順
   - 依存関係があるIssueは被依存側を先に

5. **スナップショット作成**
   ```bash
   SNAPSHOT_BRANCH="pre-auto/$(date +%Y%m%d-%H%M%S)"
   git branch "$SNAPSHOT_BRANCH" main
   echo "スナップショット作成: $SNAPSHOT_BRANCH"
   ```

6. **ユーザー確認**
   ```
   ┌─────────────────────────────────────────────────────────────┐
   │ /issue/auto 実行確認                                       │
   ├─────────────────────────────────────────────────────────────┤
   │ 処理対象Issue:                                             │
   │   1. #2: 仕様書PDFをMarkdownに変換                        │
   │   2. #3: Pydantic v2モデル化 (depends on #2)              │
   │   3. #4: テストコード作成                                  │
   │                                                             │
   │ スナップショット: pre-auto/20260311-153000                 │
   │                                                             │
   │ 品質チェックが通れば各Issueを自動マージします。           │
   │ 問題があれば処理を停止します。                             │
   │                                                             │
   │ 実行しますか？                                             │
   │ [はい、全て自動で進める]                                   │
   │ [各マージ前に確認する]                                     │
   │ [キャンセル]                                               │
   └─────────────────────────────────────────────────────────────┘
   ```

### Phase 1-N: 各Issueの処理

各Issueに対して以下を実行:

#### Step 1: Issue開始

**`/issue/start` スキルを呼び出してWorktreeとブランチを作成**:

```
Skill(skill="issue-start", args="#${ISSUE_ID}")
```

これにより以下が自動実行される：
- Worktree作成
- ブランチ作成
- 開始報告のコメント投稿

**注意**: /issue/start は仕様の対話を行うが、/issue/auto では auto-reviewer が代理判断するため、ユーザーとの対話はスキップして Step 1.5 に進む。

#### Step 1.5: 仕様レビュー（/review-spec）

**★★★ この Step は絶対にスキップしない ★★★**

review-spec はユーザーとの対話ではなく **セルフチェック** です。
自動処理であっても必ず実行し、仕様の品質を担保してください。

1. **既存仕様ファイルの確認**
```bash
SPEC_FILE=".spec/issues/${ISSUE_ID}-*.md"
if ls $SPEC_FILE 2>/dev/null; then
  echo "既存の仕様ファイルを使用"
else
  echo "仕様ファイルがありません。review-spec を実行します。"
fi
```

2. **review-spec の実行**

Task tool で `/review-spec` 相当の処理を実行：
- 5つのサブエージェント（実現性、品質、設計、Fallback計画、妥当性検証）を並列実行
- 仕様ファイルを生成

3. **auto-reviewer による代理判断**

`agents/auto-reviewer.md` の定義に従い、review-spec の結果に対して自動判断：

```
Task(subagent_type="general-purpose", prompt="
あなたは auto-reviewer エージェントです。
agents/auto-reviewer.md の定義に従って、review-spec の結果に対して判断を行ってください。

## 必ず読み込むコンテキスト
- constitution/core-rules.md
- specs/invariants.md
- specs/known-issues.md

## 判断対象
${REVIEW_SPEC_RESULT}

## 出力
1. 各判断項目への回答（許可/禁止/警告付き許可）
2. 判断理由と参照コンテキスト
3. 自信度（%）
4. 自信度 < 50% の場合は「停止」を明示

判断ログを .spec/issues/${ISSUE_ID}-auto-decisions.md に出力してください。
")
```

4. **停止判断の処理**

auto-reviewer が「停止」を返した場合：
```bash
gh issue comment $ISSUE_ID --body "## ⚠️ 自動処理停止

仕様レビューで判断できない項目があります。

### 確認が必要な項目
[auto-reviewer からの項目リスト]

手動で \`/issue/start #${ISSUE_ID}\` を実行して仕様を確定してください。"

echo "Issue #${ISSUE_ID} で停止。残りのIssue: ${REMAINING_IDS}"
exit 1
```

#### Step 2: 実装作業

**仕様ファイルを参照して実装**:

```
Task(subagent_type="general-purpose", prompt="
Issue #${ISSUE_ID} の実装を行ってください。

## Issue内容
${ISSUE_BODY}

## 仕様ファイル（必ず参照）
.spec/issues/${ISSUE_ID}-*.md

## 判断ログ（承認済みFallback等）
.spec/issues/${ISSUE_ID}-auto-decisions.md

## 完了条件
1. 仕様ファイルの検証チェックリストを全て満たす
2. 状態遷移図に沿った実装
3. 承認済みFallbackホワイトリスト以外のfallbackを使わない
4. ファイル構成計画に従う
5. 必要なテストの追加

## 重要な制約
- **コミットは行わないでください**。コミットは後のステップ（/issue/finish）で自動実行されます。
- /commit、/commit/only、/commit/push、/commit/merge などのスキルを呼び出さないでください。

実装が完了したら、検証チェックリストの各項目への対応状況を報告してください。
")
```

#### Step 3: 進捗報告
```bash
# /issue/report 相当
gh issue comment $ISSUE_ID --body "## 実装完了

### 変更内容
$(git diff --stat main)

### 品質チェック実行中..."
```

#### Step 4: 品質チェック（自動評価）

##### 4-1: コード品質チェック

**プロジェクト固有の品質チェックスクリプトを実行**:

```bash
# scripts/quality-check.sh を実行
if [ -x "./scripts/quality-check.sh" ]; then
  ./scripts/quality-check.sh
  QUALITY_OK=$?
else
  echo "Warning: scripts/quality-check.sh not found"
  QUALITY_OK=0
fi

if [ "$QUALITY_OK" -ne 0 ]; then
  echo "品質チェック失敗。処理を停止します。"
  gh issue comment $ISSUE_ID --body "## ⚠️ 品質チェック失敗

自動処理を停止しました。手動で修正してください。"
  exit 1
fi
```

**注意**: 品質チェックの具体的なコマンドは `scripts/quality-check.sh` で定義される。
プロジェクトの言語やツールに応じてスクリプトをカスタマイズすること。

##### 4-2: 仕様整合性チェック

Task tool で仕様ファイルとの整合性を検証：

```
Task(subagent_type="general-purpose", prompt="
実装が仕様ファイルに適合しているか検証してください。

## 仕様ファイル
.spec/issues/${ISSUE_ID}-*.md

## 判断ログ
.spec/issues/${ISSUE_ID}-auto-decisions.md

## 検証項目

### 1. 検証チェックリスト
仕様ファイルの「検証チェックリスト」の各項目が満たされているか確認。

### 2. 状態遷移
状態遷移図に定義された全ての状態と遷移が実装されているか確認。

### 3. Fallback ホワイトリスト
承認済みFallbackホワイトリスト以外のfallbackが使われていないか確認。

### 4. ファイル構成
ファイル構成計画に従っているか確認。

### 5. invariants.md
specs/invariants.md に反する実装がないか確認。

## 出力
各項目について ✅ / ❌ で判定し、❌ がある場合は詳細を報告。
❌ が1つでもあれば「不合格」と明示。
")
```

不合格の場合：
```bash
gh issue comment $ISSUE_ID --body "## ⚠️ 仕様整合性チェック失敗

実装が仕様ファイルに適合していません。

### 不合格項目
[検証結果からの項目]

手動で修正してください。"
exit 1
```

#### Step 5: タスク完了

**`/issue/finish` スキルを呼び出してコミット、PR作成、マージ、クリーンアップを実行**:

```
Skill(skill="issue-finish")
```

これにより以下が自動実行される（`/commit/merge` 経由）：
- 仕様ファイルのステータス更新
- コミット＆プッシュ
- PR作成＆マージ
- Worktree削除
- 完了報告のコメント投稿
- Issueクローズ

**注意**: `/issue/finish` は品質チェック（`scripts/quality-check.sh`）を再度実行する。
Step 4-1 で既に通過しているため、通常は成功するはず。

### Phase Final: 完了報告

```
┌─────────────────────────────────────────────────────────────┐
│ /issue/auto 完了                                           │
├─────────────────────────────────────────────────────────────┤
│ 処理結果:                                                   │
│   ✅ #2: 仕様書PDFをMarkdownに変換                         │
│   ✅ #3: Pydantic v2モデル化                               │
│   ✅ #4: テストコード作成                                   │
│                                                             │
│ ロールバック方法:                                           │
│   git checkout pre-auto/20260311-153000                     │
│   git reset --hard pre-auto/20260311-153000                 │
│   git push -f origin main                                   │
└─────────────────────────────────────────────────────────────┘
```

### Phase Cleanup: コンテキスト整理

全Issue処理完了後、コンテキストを整理：

```
/compact
```

**注意**: 各Issue完了時に `/issue/finish` → `/commit/merge` 経由で `/compact` が実行されるが、
全体処理完了後にも実行して最終的なコンテキストを整理する。

## Error Handling

### 品質チェック失敗時
1. 処理を停止
2. Issueにエラー報告
3. 残りのIssue一覧を表示
4. 手動修正後に `/issue/auto` で残りを継続可能

### コンテキスト上限到達時
1. 現在の状態をIssueに記録
2. サマリーに残りIssue一覧を含める
3. 新しいセッションで継続可能

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 実際の変更は行わず、処理計画のみ表示 |
| `--no-merge` | PRは作成するがマージしない |
| `--confirm-each` | 各Issue完了時に確認を求める |

## Implementation Notes

1. **子スキルの使用**: `/issue/start` と `/issue/finish` を呼び出すことで、コードの重複を避け、一貫性を保つ

2. **品質チェックスクリプト**: `scripts/quality-check.sh` を使用することで、プロジェクト固有の品質チェックを柔軟に定義可能

3. **Taskエージェントの使用**: 各Issue実装にはTaskエージェントを使用し、メインコンテキストを節約

4. **compact の実行**: 各Issue完了後に `/compact` を実行してコンテキストを整理

5. **エラー時のリカバリー**: スナップショットがあるので、いつでも元に戻せる

## Safety Checks

- ✅ 実行前にスナップショット作成
- ✅ ユーザー承認後に開始
- ✅ **out-of-date ラベル付きIssueを自動スキップ**
- ✅ **user-action ラベル付きIssueを自動スキップ**（ユーザー対応必須）
- ✅ **review-spec による仕様レビュー**（Step 1.5）
- ✅ **auto-reviewer による代理判断**（自信度 < 50% で停止）
- ✅ 品質チェック失敗で停止
- ✅ **仕様整合性チェック**（Step 4-2）
- ✅ ロールバック方法を常に表示

## Agent References

| エージェント | ファイル | 用途 |
|-------------|---------|------|
| auto-reviewer | `agents/auto-reviewer.md` | review-spec の結果に対する代理判断 |

## Script References

| スクリプト | ファイル | 用途 |
|-----------|---------|------|
| 品質チェック | `scripts/quality-check.sh` | プロジェクト固有の品質チェック（lint, test等） |

## Skill References

| スキル | 用途 |
|-------|------|
| `/issue-start` | Issue開始、Worktree作成、ブランチ作成 |
| `/review-spec` | 仕様レビュー（セルフチェック、スキップ禁止） |
| `/issue-finish` | タスク完了、コミット、PR、マージ、クリーンアップ |
