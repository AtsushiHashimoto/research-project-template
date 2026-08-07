---
description: Initialize worktree data protection configuration (run once in main repository)
---

Set up shared data storage location for worktree data protection. Run this once in the main repository before creating worktrees.

## Step 1: データ保護と worktree パスの設定

```bash
bash .claude/skills/worktree-init/init.sh
```

以下を実行します。

- 共有データ保存先の設定
- `worktree.useRelativePaths=true` の設定（ホスト / devcontainer 間で worktree を共有するため）
  - **git 2.48 以降かつ opt-in 済みの場合のみ**。要件を満たさない環境では設定されず、
    worktree は絶対パスで作られる（その場合は単一環境からのみ git を実行すること）
- 既存 worktree の `git worktree repair`
  - **相対パス化が有効なときのみ実行**。無効な環境で実行すると他環境の参照を壊すため

## Step 2: `.spec/` のプロジェクト固有内容を登録

続けて `/spec-init` を呼び出します。

```
Skill(skill="spec-init")
```

`.spec/` の3ファイルには実プロジェクトの失敗実績から抽出した**既定が同梱済み**のため、
この Step を飛ばしても `/task-run` は動作します。ただし**プロジェクト固有の失敗パターンは
既定では捕捉できない**ため、初回セットアップ時に実施することを推奨します。

後から `/spec-init` を単体で実行しても構いません（何度でも再実行可能）。
