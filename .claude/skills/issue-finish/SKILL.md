---
name: issue-finish
description: issue を完了する。検査 → 品質チェック → squash merge → close（close はここだけが行う）
argument-hint: <issue番号> [<task番号>]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Issue Finish

**PR を作ってから**、issue の worktree の中で呼ぶ。

```
bash scripts/flow/issue-finish.sh <issue番号> [<task番号>]
```

- PR 本文に `Refs #<N>` と `## /review 結果`（`/review` の各観点の判定）を書く。`Closes #<N>` は書かない
- マージ・worktree の片付け・完了報告・close はスクリプトが行う。止まったら出力の「次にやること」に従う
- 途中保存なら `/commit-push`
