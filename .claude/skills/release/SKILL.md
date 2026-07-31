---
name: release
description: 開発用ファイルを除いたクリーンな成果物を生成し GitHub Release を作成する
---

# Release

**成果物リリースから開発ハーネスを除外する。** v1.0.0 のような公開リリースに
`.claude/` / `.spec/` / `.dev/` / `worktrees/` などの開発用ファイルが混入するのを防ぐ（#102）。

```
/release v1.0.0
/release v1.0.0 --keep scripts
```

## なぜ必要か

GitHub のリリース（タグの自動 tarball や "Download ZIP"）は**リポジトリの全ファイル**を含む。
本テンプレート由来のプロジェクトでは、開発ハーネス（テンプレートが配布した作業環境）が
リポジトリに同居しているため、そのままでは成果物が開発用ファイルで汚れる。

## Workflow

### Step 1: 前提確認

```bash
git status --porcelain          # クリーンであること
git tag -l "$VERSION"           # タグの有無を確認
```

- 作業ツリーが汚れていたら停止してユーザーに確認
- タグが無ければ「タグを作成するか」をユーザーに確認してから `git tag "$VERSION"`

### Step 2: 除外内容の確認（必須）

```bash
bash scripts/release-export.sh --ref "$VERSION" --list
```

**★ 除外一覧を必ずユーザーに提示する。** 既定の除外は開発ハーネス一式
（`.claude/` `.spec/` `.dev/` `.devcontainer/` `worktrees/` `scripts/` `claude-san`
`install.sh` `docs/claude-san.md` ほか）。

**`scripts/` にプロジェクト固有のスクリプトがある場合は要注意。**
既定では除外されるため、`--keep scripts` で保持するか、固有スクリプトを
`src/` 等の成果物側に移すかをユーザーに確認する。無言で落とさない。

### Step 3: 成果物の生成

```bash
bash scripts/release-export.sh --ref "$VERSION" --out "${PROJECT}-${VERSION}.tar.gz"
```

スクリプトが末尾で「開発ハーネスが含まれていないこと」を自動検証する。

### Step 4: 内容のレビュー

```bash
tar -tzf "${PROJECT}-${VERSION}.tar.gz" | head -50
```

成果物に含まれるファイル一覧を提示し、ユーザーの承認を得る。

### Step 5: GitHub Release の作成

```bash
git push origin "$VERSION"
gh release create "$VERSION" "${PROJECT}-${VERSION}.tar.gz" \
  --title "$VERSION" --notes "$RELEASE_NOTES"
```

**リリースノートには添付 tarball がクリーン版であることを明記する**
（GitHub が自動生成する "Source code" アーカイブには開発用ファイルが含まれる旨の注記）。

## 注意

- **テンプレートリポジトリ自身には使わない。** テンプレートは開発ハーネスそのものが
  製品であり、除外すると空になる
- 除外リストの実体は `scripts/release-export.sh` の `DEFAULT_EXCLUDES`（単一情報源）。
  変更する場合はスクリプト側を編集する

## Related Skills

| スキル | 関係 |
|-------|------|
| `/commit-merge` | リリース前に作業をマージしておく |
| `/worktree-safe-remove` | リリース前の worktree 掃除 |
