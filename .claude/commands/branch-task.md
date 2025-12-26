---
description: Create a child issue in current branch without switching worktree
argument-hint: [short-description]
---

# Branch Task（子タスク作成）

現在のブランチ/worktree内で子Issueを作成し、worktreeを切り替えずに作業を継続します。

**用途**: 大きなタスクを細かく分割して進めたい場合、または関連する小タスクを同じworktree内で処理したい場合。

## Usage

```
/branch-task データ前処理の実装
```

## Workflow

1. **現在のブランチから親Issue番号を取得**
   - ブランチ名から自動抽出（例: `feature/5-description` → Issue #5）

2. **子Issueを作成**
   - タイトル: 引数から生成
   - 親Issueへの参照を含める
   - ラベル: 自動判定

3. **親Issueに子Issue作成を報告**
   - 親Issueのコメントに子Issueへのリンクを追加

4. **現在のworktreeで作業を継続**
   - ブランチは切り替えない
   - 子Issueに関連するコミットは `Refs #CHILD_ISSUE_ID` を使用
   - 必要に応じて親Issueも参照: `Refs #PARENT_ISSUE_ID, #CHILD_ISSUE_ID`

## Implementation

現在のブランチから親Issue番号を取得:
```bash
BRANCH=$(git branch --show-current)
PARENT_ISSUE_ID=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# エラーチェック
if [ -z "$PARENT_ISSUE_ID" ]; then
    echo "Error: Could not extract parent Issue ID from branch name: $BRANCH"
    echo "Branch name must contain Issue number (e.g., feature/123-description)"
    exit 1
fi
```

子Issueを作成:
```bash
CHILD_ISSUE_TITLE="$1"

gh issue create \
  --title "$CHILD_ISSUE_TITLE" \
  --body "親Issue: #${PARENT_ISSUE_ID}

## 概要
[子タスクの詳細説明]

## 親タスクとの関連
このIssueは #${PARENT_ISSUE_ID} のサブタスクです。

## 作業場所
- ブランチ: \`${BRANCH}\`
- Worktree: 親タスクと同じ" \
  --label "subtask"
```

子Issue番号を取得:
```bash
CHILD_ISSUE_ID=$(gh issue list --limit 1 --json number --jq '.[0].number')
```

親Issueに報告:
```bash
gh issue comment "$PARENT_ISSUE_ID" --body "## 子タスク作成

子Issue #${CHILD_ISSUE_ID} を作成しました。

- タイトル: ${CHILD_ISSUE_TITLE}
- 作業場所: 同一worktree内（ブランチ: \`${BRANCH}\`）
"
```

子Issueに開始報告:
```bash
gh issue comment "$CHILD_ISSUE_ID" --body "## タスク開始

親Issue #${PARENT_ISSUE_ID} と同じworktree内で作業を開始します。

- ブランチ: \`${BRANCH}\`
- コミット時の参照: \`Refs #${CHILD_ISSUE_ID}\`
"
```

## コミット時の参照方法

子タスク作業時のコミット:
```bash
git commit -m "feat(scope): implement child task feature

子タスクの実装

Refs #${CHILD_ISSUE_ID}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

親タスクにも関連する変更の場合:
```bash
git commit -m "refactor(scope): improve parent task structure

親タスクの構造改善（子タスク #${CHILD_ISSUE_ID} に関連）

Refs #${PARENT_ISSUE_ID}, #${CHILD_ISSUE_ID}

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

## Output

- 子Issue URL
- 子Issue番号
- 親Issueへのリンク
- 現在のブランチ名
- 次のステップの案内

## Use Cases

### ケース1: 大きなタスクの分割

親Issue #5「データセットローダーの実装」を進めている途中で、細かいサブタスクに分割:

```bash
/branch-task 画像前処理パイプラインの実装
/branch-task データ拡張機能の追加
/branch-task バッチ処理の最適化
```

すべて同じworktree内で順次作業し、各サブタスクごとにコミット＆報告。

### ケース2: 関連する小タスク

親Issue #7「モデルアーキテクチャの設計」の中で発見した関連タスク:

```bash
/branch-task ハイパーパラメータ設定の追加
/branch-task モデル評価スクリプトの作成
```

### ケース3: バグ修正の発見

Feature開発中に見つけたバグを別Issueとして管理:

```bash
/branch-task 画像読み込み時のメモリリーク修正
```

## Note

- **worktree切り替えなし**: `/start-task` と異なり、新しいworktreeを作成しません
- **親子関係の明示**: Issue本文とコメントで親子関係を明確に記録
- **柔軟なコミット**: 子Issue番号のみ、または親子両方を参照可能
- **並行作業**: 複数の子Issueを同時に進めることも可能（すべて同じブランチ内）

## vs /start-task

| 特徴 | /start-task | /branch-task |
|------|-------------|-------------|
| **Worktree** | 新規作成 | 現在のまま |
| **ブランチ** | 新規作成 | 現在のまま |
| **用途** | 独立した新タスク | 現在のタスクの子タスク |
| **並行作業** | 完全に独立 | 同一ブランチ内で順次 |
| **クリーンアップ** | Worktree削除必要 | 不要 |
