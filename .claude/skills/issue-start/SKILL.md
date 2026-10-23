---
name: issue-start
description: issue に着手する。ブランチと worktree を用意する（task の子は task 単位で共有）
argument-hint: <issue番号>
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Issue Start

```
bash scripts/flow/issue-start.sh <issue番号>
```

- **出力の `cd` 先へ移ること**（子プロセスは呼び出し元の作業ディレクトリを変えられない）
- ブランチ名と worktree の場所・接頭辞はスクリプトが決める（`scripts/flow/lib.sh` の `branch_prefix`）
- 新規 issue は `/issue-create` で作ってから呼ぶ。同じ worktree で小タスクを分けるなら `/issue-branch`
- 手順と次にやることは出力の「次にやること」に従う
