---
description: Commit, push, merge, and complete task with quality review (タスク完了)
argument-hint: [--auto | auto]
---

# Commit & Push & Merge（タスク完了）

変更をコミット＆プッシュ＆マージし、タスクを完全に完了する。

**重要**:
- このコマンドはタスク完了時のみ使用
- 途中保存は `/commit/push` を使用
- **Issueをクローズ**し、Worktreeを削除する
- Issueをクローズしたくない場合は `/commit/push` を使用

## Auto-Approval モード

```bash
/commit/merge              # 従来通り確認あり
/commit/merge --auto       # 品質チェック通過で自動承認
/commit/merge auto         # 同上（自然言語）
```

**Auto-Approval の動作**:
- 品質チェック（`scripts/quality-check.sh`）がパス → 自動で Phase 1 へ進む
- 品質チェック失敗 → 自動修正を試行 → 再失敗なら停止
- 観点レビュー（Step 3）で重大な問題 → 停止してエラー報告

`/issue/auto` から呼び出された場合は自動的に auto モードで動作する。

## vs /commit/push

| 特徴 | /commit/merge | /commit/push |
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

#### Step 0: QA回答の確認

タスク完了前に未確認のQA回答がないか確認：

```bash
# docs/qa/answers.jsonl をチェック
if [ -f "docs/qa/questions.jsonl" ]; then
  echo "QA回答を確認中..."
fi
```

新しい回答がある場合：
- 回答内容を表示
- 仮決定と異なる場合は、変更が必要か確認
- **仮決定と異なる回答があれば、実装を修正してから続行**

未回答の質問がある場合：
- 質問リストを表示
- タスク完了後にフォローアップIssueを作成（`/issue/finish` の Step 0 で処理）

**Auto-Approval モード時**: QA回答の確認はスキップする（`/issue/auto` の Phase 0 で既に処理済み）。

#### Step 1: 変更内容を確認
   ```bash
   git status
   git diff --stat
   ```

2. **品質チェックスクリプトを実行**
   ```bash
   # プロジェクト固有の品質チェックスクリプトを実行
   if [ -x "./scripts/quality-check.sh" ]; then
     ./scripts/quality-check.sh
   else
     echo "Warning: scripts/quality-check.sh not found or not executable"
     echo "Skipping automated quality checks"
   fi
   ```

   スクリプトが失敗した場合は修正を提案し、再実行する。

3. **観点レビューを実施**
   以下の観点でコードをレビュー：
   - ✓ **Issue目的との整合性**: 当初のIssue要件を満たしているか
   - ✓ **プロジェクトルール遵守**: `.claude/CLAUDE.md` で定義されたルール（コミット規則、ブランチ命名規則、開発ガイドライン等）に従っているか
   - ✓ **既存コードとの一貫性**: 命名規則、コーディングスタイル、アーキテクチャパターンが既存コードと統一されているか
   - ✓ **ハードコーディングの有無**: マジックナンバー、固定パス、環境依存値が設定ファイルや定数に抽出されているか
   - ✓ **ポータビリティ**: 他の環境でも動作するか（想定環境は `.claude/CLAUDE.md` に記載。未記載の場合はユーザーと確認）
   - ✓ **データ保護設計**: 重要データが `data/shared/` に保存され、Worktree削除時に失われない設計になっているか
   - ✓ **依存関係の永続化**: 新規パッケージがdevcontainer rebuild後も利用可能か
     - 仕様ファイル（`.claude/spec/issues/`）に記載のパッケージが追加されているか
     - Python: `pyproject.toml` に追加されているか
     - システム: `Dockerfile` に追加されているか
     - 仕様変更で追加したパッケージも同様にチェック
   - ✓ **セキュリティ**: 脆弱性、機密情報の漏洩チェック
   - ✓ **ドキュメント**: READMEやコメントの更新

   ※ lint, type check, テストは Step 2 の `scripts/quality-check.sh` で実施済み

4. **レビュー結果の提示**
   - 問題があれば修正提案を提示
   - 問題なければ次フェーズへの進行を提案

5. **承認判定**

   **Auto-Approval モードの判定**:
   - 引数に `--auto` または `auto` が含まれる場合 → Auto-Approval
   - `/issue/auto` から呼び出された場合 → Auto-Approval
   - それ以外 → ユーザー承認待ち

   **Auto-Approval モード**:
   - 品質チェック（Step 2）がパス → 自動で Phase 1 へ進む
   - 品質チェック失敗 → 自動修正を試行 → 再失敗なら停止してエラー報告
   - 観点レビュー（Step 3）で重大な問題 → 停止してエラー報告

   **通常モード（ユーザー承認待ち）**:
   ```
   品質チェックが完了しました。

   【レビュー結果】
   - Issue目的との整合性: ✅/❌
   - プロジェクトルール遵守: ✅/❌
   - 既存コードとの一貫性: ✅/❌
   - ハードコーディング: ✅ なし / ❌ あり
   - ポータビリティ: ✅/❌
   - データ保護設計: ✅/❌
   - 依存関係の永続化: ✅/❌
   - テスト実施: ✅/❌
   - コード品質: ✅/❌
   - セキュリティ: ✅/❌

   この内容で commit&push&merge を実行しますか？
   - ✅ はい → Phase 1へ進む
   - ❌ いいえ → 修正して再レビュー
   ```

### Phase 1: Commit & Push（承認後のみ実行）

6. **ステージング＆コミット**
   ```bash
   git add .
   git commit -m "適切なコミットメッセージ

   Closes #${ISSUE_ID}

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

7. **プッシュ**
   ```bash
   git push -u origin $(git branch --show-current)
   ```

### Phase 2: PR作成

8. **PR作成**
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

### Phase 3: マージ＆クリーンアップ

9. **マージ＆クリーンアップスクリプトを実行**

    Worktree内からでも安全にマージ＆クリーンアップを行うスクリプトを使用：

    ```bash
    # PR番号を取得（直前のgh pr createの出力から、またはgh pr listで確認）
    PR_NUMBER=$(gh pr list --head "$(git branch --show-current)" --json number --jq '.[0].number')

    # worktreeパスとメインリポジトリパスを取得
    WORKTREE_PATH=$(pwd)
    MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')

    # メインリポジトリに移動してからスクリプトを実行
    # ★ cd を先に行うことで、worktree削除後もClaudeのcwdが有効なまま
    cd "$MAIN_REPO"
    ./scripts/commit-merge.sh "$PR_NUMBER" "$WORKTREE_PATH"
    ```

    このスクリプトは以下を自動で実行：
    - PRのsquash merge
    - mainブランチの更新
    - Worktreeの削除（第2引数で指定）
    - リモートブランチの削除
    - ローカルブランチの削除

    **ポイント**: スクリプト実行前に `cd "$MAIN_REPO"` することで、worktree削除後もClaudeのcwdが有効なままになります。

### Phase 4: Issue完了

10. **Issueに完了報告**
    ```bash
    gh issue comment ${ISSUE_ID} --body "✅ タスク完了

    - ✅ 品質チェック実施
    - ✅ コードレビュー完了
    - ✅ PR作成＆マージ
    - ✅ クリーンアップ完了"
    ```

11. **Issueクローズ**（PRマージで自動クローズされなかった場合）
    ```bash
    gh issue close ${ISSUE_ID}
    ```

### Phase 5: コンテキスト整理

12. **コンテキスト整理**
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

Phase 0-5 を順次実行してください。

**重要**: Phase 0 のユーザー承認なしでは Phase 1 以降に進まないこと（Auto-Approval モード時は品質チェック通過をもって自動承認とする）。

## Safety Checks

- **Phase 0**: レビュー結果が不合格の場合は中断（ユーザー承認で全工程を実行）
- **Phase 3**: `scripts/commit-merge.sh` がworktree検出とクリーンアップを自動処理

## Output

- レビュー結果サマリー
- PR URL
- マージ結果
- クリーンアップ完了メッセージ
- 次のタスクへの準備完了通知
