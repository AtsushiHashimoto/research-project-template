---
description: Commit and push changes (途中保存)
---

# Commit & Push（途中保存）

変更をコミット＆プッシュ（途中保存、Issueは開いたまま）

**重要**:
- このコマンドは**途中保存**用です
- Issueは**クローズしません**
- Worktreeは**削除しません**
- タスク完了時は `/finish-task` または `/commit-merge` を使用

## vs /commit-merge

| 特徴 | /commit-push | /commit-merge |
|------|-------------|---------------|
| **目的** | 途中保存 | タスク完了 |
| **レビュー** | 簡易 | 品質チェック |
| **PR作成** | ❌ なし | ✅ 作成 |
| **マージ** | ❌ なし | ✅ squash merge |
| **Issueクローズ** | ❌ しない | ✅ する |
| **Worktree削除** | ❌ しない | ✅ する |

## Workflow

### Phase 0: 簡易レビュー

1. **変更内容を確認**
   ```bash
   git status
   git diff --stat
   ```

2. **簡易品質チェック**
   以下の観点で変更をチェック：
   - ✓ **明らかな問題**: 未完成のコード、デバッグ用コード、コメントアウトされたコード
   - ✓ **セキュリティ**: 機密情報の混入（API key、password等）
   - ✓ **データ保護**: 重要データが `data/local/` ではなく `data/shared/` に保存される設計か
   - ✓ **ハードコーディング**: 明らかなマジックナンバーや固定パスがないか
   - ✓ **テスト**: テストの追加が必要な変更がないか

3. **問題があれば指摘**
   - 重大な問題: コミット前に修正を提案
   - 軽微な問題: 注意点として報告しつつコミット続行

### Phase 1: Commit & Push

4. **すべての変更をステージング**
   ```bash
   git add .
   ```

5. **コミット**
   - Conventional Commits 形式を使用
   - Issue番号を含める（`Refs #ISSUE_ID`）
   - Claude Code署名を含める

6. **プッシュ**
   ```bash
   git push -u origin $(git branch --show-current)
   ```

### Phase 2: 進捗報告

7. **Issueに進捗報告**
   - コミットハッシュ
   - 変更ファイル数
   - 次のステップ

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

変更をステージング＆コミット：
```bash
git add .
git commit -m "適切なコミットメッセージ

Refs #${ISSUE_ID}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

プッシュ：
```bash
git push -u origin $(git branch --show-current)
```

Issueに報告：
```bash
gh issue comment "$ISSUE_ID" --body "## コミット完了（途中保存）

- コミット: [hash]
- 変更: [files]
- 次のステップ: [...]

---
*Issueは開いたままです。タスク完了時は `/finish-task` を実行してください。*"
```

## Output

- 簡易レビュー結果（問題があれば）
- コミットハッシュ
- 変更ファイル数
- Issue コメント URL
- 次のステップの案内

## Note

このコマンドは**途中保存**用です。
タスクが完了したら `/finish-task` を実行してください。
