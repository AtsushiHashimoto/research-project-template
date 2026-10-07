<!-- [Template] research-project-template 由来。プロジェクト固有の記述は AGENTS.md に書くこと -->

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
bash scripts/worktree-relative.sh add worktrees/issueN -b feature/N-description
```

- **worktree の `.git` 参照は相対パスにする（必須）。** ホストと devcontainer（`/workspace`）で絶対パスが違うため、
  絶対パスで作ると作成した側の環境でしか git / gh が動かない。
- **`git worktree add` を直接呼ばず、`scripts/worktree-relative.sh add` を通す。** 作成直後に worktree 側の
  `.git` を相対化する（git のバージョンによらず同じ方式）。メイン側 `.git/worktrees/<id>/gitdir` は絶対パスのまま
  （相対にすると git < 2.48 がカレントディレクトリ基準で解決し、`git worktree prune` が管理情報を消す）。
- **`--relative-paths` / `worktree.useRelativePaths`（git 2.48+）は使わない。** リポジトリに
  `extensions.relativeWorktrees` が書かれ、git < 2.48 の環境（ホストとコンテナで版が違う場合）がリポジトリを開けなくなる。
- 別環境で worktree 一覧が prunable になったら、その環境で `bash scripts/worktree-relative.sh fix` を実行する
  （`scripts/configure-worktree-paths.sh` が devcontainer 作成時・`/worktree-init` 時に自動で呼ぶ）。
- 重要データは worktree 内ではなく `data/shared/` に置く（`data-protection.md`）
