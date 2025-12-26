---
description: Commit changes only (no push)
---

# Commit Only（ローカル保存）

変更をコミットのみ（プッシュしない）

**用途**: 一時的にローカルに変更を保存したい場合

## Workflow

### Phase 0: 簡易レビュー

1. **変更内容を確認**
   ```bash
   git status
   git diff --stat
   ```

2. **簡易チェック**
   - 明らかな問題（デバッグコード、未完成のコード等）がないか確認
   - 問題があれば指摘

### Phase 1: Commit

3. **すべての変更をステージング**
   ```bash
   git add .
   ```

4. **コミット**
   - Conventional Commits 形式を使用
   - Issue番号を含める（`Refs #ISSUE_ID`）
   - Claude Code署名を含める

## Implementation

現在のブランチから Issue 番号を取得：
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

変更をステージング：
```bash
git add .
```

コミット（適切なメッセージで）：
```bash
git commit -m "適切なコミットメッセージ

Refs #${ISSUE_ID}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Output

- 簡易レビュー結果（問題があれば）
- コミットハッシュ
- 変更ファイル数
- 次のステップの案内（push: `/commit push`、完了: `/finish-task`）
