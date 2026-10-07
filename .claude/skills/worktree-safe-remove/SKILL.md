---
name: worktree-safe-remove
description: Safely remove a worktree after checking for important data
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


Safely remove a worktree. Checks data/local for important files and warns before deletion. Preserves data/shared.

Execute the script:

```bash
bash .claude/skills/worktree-safe-remove/safe-remove.sh
```
