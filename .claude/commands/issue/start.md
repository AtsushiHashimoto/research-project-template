---
description: Start a new task with GitHub issue, branch, and worktree setup
argument-hint: [short-description]
---

# Start Task Workflow

新しいタスクを開始します。GitHub Issue の作成、ブランチ作成、Worktree 作成、仕様レビューを自動的に実行します。

## Usage

```
/issue/start データセットローダーの実装
```

## Workflow

1. **GitHub Issue を作成**
   - タイトル: 引数から生成
   - ラベル: ユーザーに選択させる（下記参照）
   - Assignee: 自分を設定（通知を受け取るため）
   - 詳細な説明を含める

2. **ブランチを作成**
   - 命名規則: `{type}/ISSUE_ID-description`
   - 例: `feature/5-add-dataset-loader`, `survey/3-related-work`

3. **Worktree を作成**
   - パス: `../project-name-issueN`
   - ブランチと連携

4. **作業開始の準備**
   - Worktree ディレクトリに移動
   - 初期報告を Issue に投稿

5. **仕様の対話**
   - ユーザーと仕様について対話
   - 要件、制約、想定されるエッジケースを確認

6. **仕様レビュー（/review-spec）**
   - 4つのサブエージェントで仕様をレビュー
   - 状態遷移図、ログ戦略、ファイル構成計画を生成
   - Fallback分岐の承認をユーザーに確認
   - 検証チェックリストを生成
   - `.claude/spec/issues/{issue_id}-{description}.md` に保存

7. **Plan Mode**
   - 仕様が固まったら plan-mode に移行
   - 実装計画を策定

## Label Selection

Issue作成時にユーザーに確認する：

```
どの種類のタスクですか？
1. feature   - 新機能追加
2. bug       - バグ修正
3. survey    - 文献・ライブラリ調査 → docs/surveys/
4. experiment - 仮説検証 → data/shared/experiments/
5. validation - 動作確認
6. docs      - ドキュメント
7. refactor  - リファクタリング
8. chore     - CI・依存関係など
```

選択されたラベルに応じてブランチプレフィックスを決定：
- feature, validation, refactor, chore → `feature/`
- bug → `fix/`
- survey → `survey/`
- experiment → `experiment/`
- docs → `docs/`

## Implementation

現在の状態を確認:
```bash
git status
git worktree list
```

Issue を作成（自分をAssigneeに設定して通知を受け取る）:
```bash
gh issue create --title "$TASK_DESCRIPTION" --body "詳細な説明" --label "$LABEL" --assignee @me
```

Worktree とブランチを作成:
```bash
ISSUE_ID=$(gh issue list --limit 1 --json number --jq '.[0].number')
DESCRIPTION=$(echo "$TASK_DESCRIPTION" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WORKTREE_PATH="../${REPO_NAME}-issue${ISSUE_ID}"

git worktree add "$WORKTREE_PATH" -b "${BRANCH_PREFIX}/${ISSUE_ID}-${DESCRIPTION}"
```

Issue に開始報告:
```bash
gh issue comment "$ISSUE_ID" --body "## タスク開始

- ブランチ: \`${BRANCH_PREFIX}/${ISSUE_ID}-${DESCRIPTION}\`
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
