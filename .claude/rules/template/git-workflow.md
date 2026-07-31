<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## コミットのルール

- コミットメッセージには必ず Issue を参照: `Fixes #ISSUE_ID` または `Refs #ISSUE_ID`
- Conventional Commits 形式を推奨:
  - `feat(scope): description` - 新機能
  - `fix(scope): description` - バグ修正
  - `docs(scope): description` - ドキュメント
  - `refactor(scope): description` - リファクタリング
  - `test(scope): description` - テスト追加

---

## プルリクエストのルール

- ブランチでの作業完了後、PR を作成
- PR タイトルに Issue 番号を含める
- PR 説明に `Closes #ISSUE_ID` を記載してリンク

---

## Git Worktree 管理

### Worktree 作成の標準パターン

```bash
# 新しい Issue #N のブランチと worktree を作成
git worktree add --relative-paths worktrees/issueN feature/N-description
cd worktrees/issueN
```

### ★ `--relative-paths` が必須な理由

`git worktree add` は既定で `.git` 参照を**絶対パス**で2箇所に書き込む:

```
worktrees/issueN/.git        → gitdir: <絶対パス>/.git/worktrees/issueN
.git/worktrees/issueN/gitdir → <絶対パス>/worktrees/issueN/.git
```

devcontainer はリポジトリを `/workspace` にマウントするため、**ホストとコンテナで絶対パスが一致しない**。
結果として **worktree を作成した側の環境でしか git / gh が動かない**（双方向に壊れる）。

| 作成場所 | 書き込まれるパス | 壊れる環境 |
|---|---|---|
| devcontainer 内 | `/workspace/...` | ホスト |
| ホスト | `/Users/...` | devcontainer 内 |

`--relative-paths` を付けると相対パスで書かれ、両環境から解決できる（git 2.48 以降）。

`scripts/configure-worktree-paths.sh` が `worktree.useRelativePaths=true` を設定するため、
通常は自動で有効になる（devcontainer 起動時と `/worktree-init` 実行時）。
上記のコマンド例で明示しているのは、設定が無い環境でも安全にするため。

### 既存の壊れた worktree を復旧する

```bash
# 現在の環境から見た正しいパスに書き換える
git worktree repair
```

**実行した環境でのみ有効**なので、恒久対策は相対パス化のほう。

### 並行作業の例

```
project-name/                    # メインリポジトリ
├── worktrees/                   # Worktree用ディレクトリ（.gitignore対象）
│   ├── issue5/                  # feature/5-description
│   ├── issue7/                  # survey/7-description
│   └── issue9/                  # fix/9-description
├── data/
│   └── shared/                  # 共有データ（全worktreeからアクセス可能）
└── src/                         # メインブランチのソース
```
