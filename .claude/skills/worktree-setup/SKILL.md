---
name: worktree-setup
description: Set up data directories in a new worktree
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


Run this after creating a new worktree to set up data/shared (symlink) and data/local (temporary) directories.

Execute the script:

```bash
bash .claude/skills/worktree-setup/setup.sh
```
