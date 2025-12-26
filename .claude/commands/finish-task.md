---
description: Finish task with quality review by invoking commit-merge workflow (タスク完了)
---

# Finish Task（タスク完了）

タスクを完了します。`/commit-merge` のエイリアスです。

## 用途

**タスクが完全に完了した時に使用**します。

以下を実行します：
1. 品質レビュー（Issue目的との整合性確認）
2. Commit & Push
3. PR作成 & マージ
4. **Issueクローズ**
5. Worktree削除
6. コンテキスト整理（/compact）

## Usage

```
/finish-task
```

## vs /commit-push（途中保存）

タスクが**まだ完了していない**場合は `/commit-push` を使用してください。

| スキル | 用途 | Issueクローズ | Worktree削除 |
|-------|------|--------------|--------------|
| `/finish-task` | タスク完了 | ✅ する | ✅ する |
| `/commit-push` | 途中保存 | ❌ しない | ❌ しない |

## Implementation

Skillツールを使って `/commit-merge` コマンドを実行：

```xml
<invoke name="Skill">
<parameter name="skill">commit-merge</parameter>
</invoke>
```

すべての実装詳細は `/commit-merge` コマンドに委譲されます。

## Note

- `/finish-task` と `/commit-merge` は**同じ動作**をします
- どちらもタスク完了時に使用（Issueをクローズする）
- 途中保存したい場合は `/commit-push` を使用
