---
name: issue-branch
description: いまの worktree の中で小タスク（子 issue）を作る。ブランチも worktree も切り替えない
argument-hint: --title <題> [--type <T>]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Issue Branch（小タスク）

```
bash scripts/flow/issue-branch.sh --title <題> [--type <T>]
```

- `--type` の既定は `feature`。親はいまのブランチ名の番号（task 単位のブランチなら task）
- 小タスクは親と同じブランチで作業し、`Refs #<子>` でコミットする
- 手順と次にやることは出力の「次にやること」に従う
