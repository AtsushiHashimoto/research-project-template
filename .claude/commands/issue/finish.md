---
description: Finish task with quality review by invoking commit/merge workflow (タスク完了)
---

# Finish Task（タスク完了）

タスクを完了します。`/commit/merge` のエイリアスです。

## 用途

**タスクが完全に完了した時に使用**します。

以下を実行します：
1. 品質レビュー（Issue目的との整合性確認）
2. **仕様ファイルのステータス更新**（completed）
3. Commit & Push
4. PR作成 & マージ
5. **Issueクローズ**
6. Worktree削除
7. コンテキスト整理（/compact）

## Usage

```
/issue/finish
```

## vs /commit/push（途中保存）

タスクが**まだ完了していない**場合は `/commit/push` を使用してください。

| スキル | 用途 | Issueクローズ | Worktree削除 |
|-------|------|--------------|--------------|
| `/issue/finish` | タスク完了 | ✅ する | ✅ する |
| `/commit/push` | 途中保存 | ❌ しない | ❌ しない |

## Implementation

### Step 1: 仕様ファイルのステータス更新

```bash
# Issue番号の取得
BRANCH=$(git branch --show-current)
ISSUE_ID=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# 仕様ファイルを特定
SPEC_FILE=$(ls .claude/spec/issues/${ISSUE_ID}-*.md 2>/dev/null | head -1)
```

仕様ファイルが存在する場合、メタ情報を更新：
- `ステータス: draft` → `ステータス: completed`
- `完了日: YYYY-MM-DD` を追加
- 変更履歴に完了記録を追加

### Step 2: /commit/merge 実行

Skillツールを使って `/commit/merge` コマンドを実行：

```xml
<invoke name="Skill">
<parameter name="skill">commit/merge</parameter>
</invoke>
```

すべての実装詳細は `/commit/merge` コマンドに委譲されます。

## Note

- `/issue/finish` は仕様ファイルのステータス更新 + `/commit/merge` を実行
- どちらもタスク完了時に使用（Issueをクローズする）
- 途中保存したい場合は `/commit/push` を使用
