---
description: Report progress on current task to GitHub issue
---

# Report Progress

現在のタスクの進捗を GitHub Issue に報告します。

## Usage

```
/report-progress
```

## Workflow

1. **現在のブランチから Issue 番号を抽出**
   - ブランチ名: `feature/3-description` → Issue #3

2. **変更内容を確認**
   - `git diff --stat` で変更ファイルを確認
   - `git status` で追加/変更/削除を確認

3. **進捗報告を自動生成**
   - 完了した作業
   - 変更されたファイル
   - 次のステップ

4. **Issue にコメント投稿**
   - Markdown形式で整形
   - タイムスタンプを含める

## Implementation

現在のブランチから Issue 番号を取得:
```bash
BRANCH=$(git branch --show-current)
ISSUE_ID=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# エラーチェック
if [ -z "$ISSUE_ID" ]; then
    echo "Error: Could not extract Issue ID from branch name: $BRANCH"
    echo "Branch name must contain Issue number (e.g., feature/123-description)"
    exit 1
fi
```

変更内容を確認:
```bash
git diff --stat HEAD
git status --short
```

進捗報告を生成して投稿:
```bash
gh issue comment "$ISSUE_ID" --body "
## 進捗報告 ($(date '+%Y-%m-%d %H:%M'))

### 完了した作業
- [変更内容のサマリー]

### 変更ファイル
\`\`\`
$(git diff --stat HEAD)
\`\`\`

### 次のステップ
- [次にやること]
"
```

## Output

- Issue コメント URL
- 報告内容のサマリー

## Note

このコマンドは任意のタイミングで使用できます。
進捗の区切りで定期的に実行することを推奨します。
