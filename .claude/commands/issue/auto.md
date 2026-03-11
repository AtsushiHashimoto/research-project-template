---
description: Automatically process multiple issues in sequence (複数Issueの自動処理)
argument-hint: [issue_ids...]
---

# Issue Auto-Processing

複数のIssueを自動的に順番に処理します。

## Usage

```
/issue/auto 2 3 4        # Issue #2, #3, #4 を順番に処理
/issue/auto 2,3,4        # カンマ区切りも可
/issue/auto --all-open   # 全てのopen Issueを処理
```

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

1. **引数解析**
   ```bash
   # Issue IDのリストを取得
   ISSUE_IDS="$ARGUMENTS"
   # カンマをスペースに変換
   ISSUE_IDS=$(echo "$ISSUE_IDS" | tr ',' ' ')
   ```

2. **依存関係の解析**
   ```bash
   # 各Issueの情報を取得
   for ID in $ISSUE_IDS; do
     gh issue view $ID --json title,body,labels
   done
   ```

   Issue本文に `depends on #N` や `blocked by #N` があれば順序を調整。

3. **処理順序の決定**
   - 依存関係がないIssueは番号順
   - 依存関係があるIssueは被依存側を先に

4. **スナップショット作成**
   ```bash
   SNAPSHOT_BRANCH="pre-auto/$(date +%Y%m%d-%H%M%S)"
   git branch "$SNAPSHOT_BRANCH" main
   echo "スナップショット作成: $SNAPSHOT_BRANCH"
   ```

5. **ユーザー確認**
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
```bash
# /issue/start 相当の処理
ISSUE_ID=$CURRENT_ID
ISSUE_INFO=$(gh issue view $ISSUE_ID --json title,body)
ISSUE_TITLE=$(echo "$ISSUE_INFO" | jq -r '.title')

# ブランチ名生成
BRANCH_NAME="feature/${ISSUE_ID}-$(echo "$ISSUE_TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-30)"

# Worktree作成
WORKTREE_PATH="worktrees/issue${ISSUE_ID}"
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
cd "$WORKTREE_PATH"

# 開始報告
gh issue comment $ISSUE_ID --body "## 🤖 自動処理開始

\`/issue/auto\` による自動処理を開始します。

- ブランチ: \`$BRANCH_NAME\`
- Worktree: \`$WORKTREE_PATH\`"
```

#### Step 2: 実装作業
Taskエージェントを使用して実装:
```
Task(subagent_type="general-purpose", prompt="
Issue #${ISSUE_ID} の実装を行ってください。

Issue内容:
${ISSUE_BODY}

完了条件:
1. Issue要件を満たす実装
2. 必要なテストの追加
3. ドキュメント更新（必要な場合）

実装が完了したら、変更内容のサマリーを報告してください。
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
```bash
# 品質チェックツール実行
QUALITY_OK=true

# ruff check
if [ -f "pyproject.toml" ]; then
  uv run ruff check src/ || QUALITY_OK=false
  uv run ruff format --check src/ || QUALITY_OK=false
  uv run mypy src/ || QUALITY_OK=false
  uv run pytest || QUALITY_OK=false
fi

if [ "$QUALITY_OK" = false ]; then
  echo "品質チェック失敗。処理を停止します。"
  gh issue comment $ISSUE_ID --body "## ⚠️ 品質チェック失敗

自動処理を停止しました。手動で修正してください。"
  exit 1
fi
```

#### Step 5: コミット＆マージ
```bash
# /commit/merge 相当（Phase 0承認済みなので自動実行）
git add .
git commit -m "feat: ${ISSUE_TITLE}

Closes #${ISSUE_ID}

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin "$BRANCH_NAME"

# PR作成＆マージ
gh pr create --title "${ISSUE_TITLE} (#${ISSUE_ID})" \
  --body "Closes #${ISSUE_ID}

## 自動処理
\`/issue/auto\` による自動処理で作成されました。

## 品質チェック
- ✅ ruff check
- ✅ ruff format
- ✅ mypy
- ✅ pytest"

gh pr merge --squash --delete-branch
```

#### Step 6: クリーンアップ
```bash
# Worktree削除
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
cd "$MAIN_REPO"
git checkout main
git pull
git worktree remove "$WORKTREE_PATH" 2>/dev/null || true
```

#### Step 7: 完了報告
```bash
gh issue comment $ISSUE_ID --body "## ✅ 自動処理完了

- ✅ 実装完了
- ✅ 品質チェック通過
- ✅ PR作成＆マージ
- ✅ クリーンアップ完了"
```

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

1. **Taskエージェントの使用**: 各Issue実装にはTaskエージェントを使用し、メインコンテキストを節約

2. **compact の実行**: 各Issue完了後に `/compact` を実行してコンテキストを整理

3. **エラー時のリカバリー**: スナップショットがあるので、いつでも元に戻せる

## Safety Checks

- ✅ 実行前にスナップショット作成
- ✅ ユーザー承認後に開始
- ✅ 品質チェック失敗で停止
- ✅ ロールバック方法を常に表示
