---
description: Start a new task with GitHub issue, branch, and worktree setup
argument-hint: [short-description]
---

# Start Task Workflow

新しいタスクを開始します。GitHub Issue の作成、ブランチ作成、Worktree 作成を自動的に実行します。

## Usage

```
/start-task データセットローダーの実装
```

## Workflow

1. **GitHub Issue を作成**
   - タイトル: 引数から生成
   - ラベル: 自動判定（feature, bug, research など）
   - 詳細な説明を含める

2. **ブランチを作成**
   - 命名規則: `feature/ISSUE_ID-description` または `research/ISSUE_ID-description`
   - Issue 番号を自動的に含める

3. **Worktree を作成**
   - パス: `../delta-clip-dev-issueN`
   - ブランチと連携

4. **作業開始の準備**
   - Worktree ディレクトリに移動
   - 初期報告を Issue に投稿

## Implementation

現在の状態を確認:
```bash
git status
git worktree list
```

Issue を作成:
```bash
gh issue create --title "$TASK_DESCRIPTION" --body "詳細な説明"
```

Worktree とブランチを作成:
```bash
ISSUE_ID=$(gh issue list --limit 1 --json number --jq '.[0].number')
DESCRIPTION=$(echo "$TASK_DESCRIPTION" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WORKTREE_PATH="../${REPO_NAME}-issue${ISSUE_ID}"

git worktree add "$WORKTREE_PATH" -b "feature/${ISSUE_ID}-${DESCRIPTION}"
```

Issue に開始報告:
```bash
gh issue comment "$ISSUE_ID" --body "## タスク開始

- ブランチ: \`feature/${ISSUE_ID}-${DESCRIPTION}\`
- Worktree: \`${WORKTREE_PATH}\`

作業を開始します。"
```

## Output

- Issue URL
- ブランチ名
- Worktree パス
- 次のステップの案内

## Note

このコマンドは Claude が自動的に実行します（CLAUDE.md の自動実行ルールに従う）。
ユーザーが明示的に呼び出すこともできます。
