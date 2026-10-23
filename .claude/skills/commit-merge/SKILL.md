---
name: commit-merge
description: squash merge と後片付けだけを行う（コミット・push・close はしない。完了は /issue-finish）
argument-hint: <issue番号> [<task番号>] [<worktree>]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Commit & Merge

**通常は `/issue-finish` を使う**（未回答 QA・仕様ステータス・完了報告・close まで行う）。
単体で使うときは PR を作ってから、worktree の中で呼ぶ。

```
bash scripts/flow/commit.sh merge <issue番号> [<task番号>] [<worktree>]
```

- worktree を渡すと、マージ後に worktree とブランチを消す（`scripts/worktree-relative.sh remove`）
- 終了コード 10 は「マージは済んだが後片付けが失敗した」。マージし直さない
