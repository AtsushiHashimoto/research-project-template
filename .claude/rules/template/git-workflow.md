<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## ★ 既定ブランチは `main` 固定

**既定ブランチは `main` を前提にする**（`master` 等は想定しない。`origin/HEAD` からの検出は失敗モードを増やすため採らない）。
`main` に切り替えられなければスクリプトは握り潰さずに停止する（#122 D4）。`master` 運用なら `main` に改名する。

## コミットのルール

- コミットメッセージには必ず Issue を参照: `Fixes #ISSUE_ID` または `Refs #ISSUE_ID`
- **`git add .` / `git add -A` を使わず、意図したファイルを名指しで stage する**（未追跡の clone・生成物が混入した事例がある）。
  commit 前に `git diff --cached --stat` で確認する
- Conventional Commits 形式を推奨（`feat` / `fix` / `docs` / `refactor` / `test`、`type(scope): description`）

## プルリクエストのルール

- ブランチでの作業が済んだら PR を作る。タイトルに Issue 番号を含め、説明に `Closes #ISSUE_ID` を書く

## Git Worktree

```bash
git worktree add --relative-paths worktrees/issueN feature/N-description
```

- **`--relative-paths` は必須。** ホストと devcontainer（`/workspace`）で絶対パスが違うため、絶対パスで作ると
  作成した側の環境でしか git / gh が動かない。`scripts/configure-worktree-paths.sh` が
  `worktree.useRelativePaths=true` を設定する。壊れた worktree は `git worktree repair`（実行した環境でのみ有効）
- 重要データは worktree 内ではなく `data/shared/` に置く（`data-protection.md`）
