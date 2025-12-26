---
description: Commit, push, merge, and complete task with quality review (タスク完了)
---

# Commit & Push & Merge（タスク完了）

変更をコミット＆プッシュ＆マージし、タスクを完全に完了する。

**重要**:
- このコマンドはタスク完了時のみ使用
- 途中保存は `/commit-push` を使用
- **Issueをクローズ**し、Worktreeを削除する
- Issueをクローズしたくない場合は `/commit-push` を使用

## vs /commit-push

| 特徴 | /commit-merge | /commit-push |
|------|--------------|--------------|
| **目的** | タスク完了 | 途中保存 |
| **品質レビュー** | ✅ 実施 | ❌ なし |
| **PR作成** | ✅ 作成 | ❌ なし |
| **マージ** | ✅ squash merge | ❌ なし |
| **Issueクローズ** | ✅ クローズ | ❌ 開いたまま |
| **Worktree削除** | ✅ 削除 | ❌ 残す |

## Workflow

### Phase 0: Quality Assurance（品質チェック）

**目的**: AI生成コードの品質を保証し、Issue目的との整合性を確認

1. **変更内容を確認**
   ```bash
   git status
   git diff --stat
   ```

2. **自動品質チェックを実施**
   以下の観点でコードをレビュー：
   - ✓ **Issue目的との整合性**: 当初のIssue要件を満たしているか
   - ✓ **プロジェクトルール遵守**: `.claude/CLAUDE.md` で定義されたルール（コミット規則、ブランチ命名規則、開発ガイドライン等）に従っているか
   - ✓ **既存コードとの一貫性**: 命名規則、コーディングスタイル、アーキテクチャパターンが既存コードと統一されているか
   - ✓ **ハードコーディングの有無**: マジックナンバー、固定パス、環境依存値が設定ファイルや定数に抽出されているか
   - ✓ **ポータビリティ**: 他の環境でも動作するか（想定環境は `.claude/CLAUDE.md` に記載。未記載の場合はユーザーと確認）
   - ✓ **データ保護設計**: 重要データが `data/shared/` に保存され、Worktree削除時に失われない設計になっているか
   - ✓ **テスト実施状況**: 必要なテストが実施されているか
   - ✓ **コード品質**: lint, type check, 重複コード、過度な複雑性
   - ✓ **セキュリティ**: 脆弱性、機密情報の漏洩チェック
   - ✓ **ドキュメント**: READMEやコメントの更新

3. **レビュー結果の提示**
   - 問題があれば修正提案を提示
   - 問題なければ次フェーズへの進行を提案

4. **Human-in-the-Loop: ユーザー承認待ち**

   **ユーザーに確認**:
   ```
   品質チェックが完了しました。

   【レビュー結果】
   - Issue目的との整合性: ✅/❌
   - プロジェクトルール遵守: ✅/❌
   - 既存コードとの一貫性: ✅/❌
   - ハードコーディング: ✅ なし / ❌ あり
   - ポータビリティ: ✅/❌
   - データ保護設計: ✅/❌
   - テスト実施: ✅/❌
   - コード品質: ✅/❌
   - セキュリティ: ✅/❌

   この内容で commit&push&merge を実行しますか？
   - ✅ はい → Phase 1へ進む
   - ❌ いいえ → 修正して再レビュー
   ```

### Phase 1: Commit & Push（承認後のみ実行）

5. **ステージング＆コミット**
   ```bash
   git add .
   git commit -m "適切なコミットメッセージ

   Closes #${ISSUE_ID}

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

6. **プッシュ**
   ```bash
   git push -u origin $(git branch --show-current)
   ```

### Phase 2: PR作成

7. **PR作成**
   ```bash
   ISSUE_TITLE=$(gh issue view "$ISSUE_ID" --json title --jq '.title')
   gh pr create \
     --title "${ISSUE_TITLE} (#${ISSUE_ID})" \
     --body "Closes #${ISSUE_ID}

   ## 変更概要
   [変更内容のサマリー]

   ## 品質チェック
   - ✅ コードレビュー実施済み
   - ✅ テスト実施済み
   - ✅ Issue要件を満たしていることを確認
   "
   ```

### Phase 3: マージ

8. **マージ確認**
   - ユーザーに「マージしますか？」と確認

9. **マージ実行**
    ```bash
    gh pr merge --squash --delete-branch
    ```

### Phase 4: クリーンアップ

10. **メインブランチに戻る＆更新**
    ```bash
    MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
    cd "$MAIN_REPO"
    git checkout main
    git pull
    ```

11. **Worktree削除**
    ```bash
    WORKTREE_PATH=$(git worktree list | grep "issue${ISSUE_ID}" | awk '{print $1}')
    git worktree remove "$WORKTREE_PATH" 2>/dev/null || true
    ```

12. **ローカルブランチ削除**
    ```bash
    git branch -d "feature/${ISSUE_ID}-"* 2>/dev/null || true
    ```

### Phase 5: Issue完了

13. **Issueに完了報告**
    ```bash
    gh issue comment ${ISSUE_ID} --body "✅ タスク完了

    - ✅ 品質チェック実施
    - ✅ コードレビュー完了
    - ✅ PR作成＆マージ
    - ✅ クリーンアップ完了"
    ```

14. **Issueクローズ**（PRマージで自動クローズされなかった場合）
    ```bash
    gh issue close ${ISSUE_ID}
    ```

### Phase 6: コンテキスト整理

15. **コンテキスト整理**
    ```
    /compact
    ```

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

Phase 0-6 を順次実行してください。

**重要**: Phase 0 のユーザー承認なしでは Phase 1 以降に進まないこと。

## Safety Checks

- **Phase 0**: レビュー結果が不合格の場合は中断
- **Phase 1**: マージ前にユーザー確認を求める
- **Phase 4**: worktree が存在しない場合はスキップ

## Output

- レビュー結果サマリー
- PR URL
- マージ結果
- クリーンアップ完了メッセージ
- 次のタスクへの準備完了通知
