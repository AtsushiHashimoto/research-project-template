<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## ★ 既定ブランチは `main` 固定

**本テンプレートは既定ブランチが `main` であることを前提にします。** `master` 等は想定しません。

worktree 運用・PR マージ後のブランチ削除・`/commit-merge` の後処理はいずれも `main` を前提に
書かれており、検出（`git symbolic-ref refs/remotes/origin/HEAD`）は `origin/HEAD` 未設定の
リポジトリやローカル専用リポジトリで失敗して**新たな分岐と失敗モードを増やす**ためです。

- `main` に切り替えられなかった場合、スクリプトは**握り潰さずに停止**します（#122 D4）。
  以前は `git checkout main 2>/dev/null || true` としていたため、
  **feature ブランチに居たまま pull と後続処理が走る**という壊れ方をしていました
- `master` 運用のリポジトリで使う場合は、ブランチを `main` に改名してください

---

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
git worktree add worktrees/issueN feature/N-description
cd worktrees/issueN
```

**`--relative-paths` フラグは書きません。** 相対パス化するかどうかは
`scripts/configure-worktree-paths.sh` が設定する `worktree.useRelativePaths` が決めます。
判定を1箇所に集約するためです（理由は次節）。

### ★ 相対パス化が必要な理由

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

相対パスで書かれていれば両環境から解決できる（git 2.48 以降）。
`scripts/configure-worktree-paths.sh` が `worktree.useRelativePaths=true` を設定すると、
`git worktree add` はフラグ無しでも相対パスで書く。同スクリプトは devcontainer 起動時と
`/worktree-init` 実行時に走るが、**設定を書くのは下記の opt-in 済みの場合だけ**。

### ★ 相対パス化には **両環境** の git 2.48 以降と opt-in が要る

**フラグを直接書いてはいけません。** git 2.48 未満では
`error: unknown option 'relative-paths'` になり、**worktree の作成そのものが失敗します。**

さらに `worktree.useRelativePaths` は**明示的な opt-in を必須**にしています。

```bash
# ホストと devcontainer の両方が git 2.48 以降であることを確認してから
git config worktree.relativePathsOptIn true
```

`.git/config` はホストと devcontainer で**同一実体**（bind mount）です。片側だけ 2.48 以降に
なった状態で相対パス化すると、古い側が壊れます。壊れ方は 2 通りあります。

| 相対パス化のしかた | 古い側で起きること |
|---|---|
| `worktree.useRelativePaths`（本来の方法） | 最初の相対 worktree 作成時に `extensions.relativeWorktrees` と `core.repositoryformatversion=1` が書かれ、**そのリポジトリの全 git コマンド**が `fatal: unknown repository extension found: relativeworktrees` で落ちる |
| 記録を手で相対パスに書き換える | 拡張が書かれないので fatal にはならないが、worktree が **prunable と誤判定**され、`git gc --auto` 経由の `git worktree prune` が**登録ごと削除**する |

バージョン判定は自分の git しか見られないため、「両方を確認した」という人間の判断を opt-in として要求します。

### ★ opt-in は実質的に片道切符

一度 `extensions.relativeWorktrees` が書かれると、古い側では `git config --unset` 自体も
落ちるため、**`.git/config` を手で編集しないと戻せません。**

```ini
# 戻す場合: .git/config を直接編集する
[core]
	repositoryformatversion = 0     ; 1 → 0
[extensions]
	relativeWorktrees = true        ; この行（と空の [extensions] セクション）を削除
[worktree]
	useRelativePaths = true         ; この行を削除
```

編集後、「正」と決めた環境から `git worktree repair` を実行して絶対パスに戻します。

### 相対パス化できない環境での運用

要件を満たさない場合、worktree は絶対パスで作られます。このとき
**worktree に対する git / gh コマンドは 1 つの環境からのみ実行してください**
（ファイルの編集はどの環境からでも可）。どの環境を正とするかはプロジェクト側で決めて
`.claude/CLAUDE.md` またはローカルルールに記録します。

### 壊れた worktree の復旧 — `git worktree repair` は「正」の環境からのみ

```bash
# 現在の環境から見た「絶対パス」で参照を上書きする
git worktree repair
```

絶対パス運用における**正しい復旧手段**です。ただし**実行した環境でのみ有効**なので、
上で「正」と決めた**1 つの環境からだけ**実行してください。ホスト側とコンテナ側の両方から
実行すると**互いの参照を壊し合い**、後から実行した側でしか git / gh が動かなくなります。

`configure-worktree-paths.sh` が repair を自動実行するのは**相対パス化が有効なときだけ**です
（無効なときに自動実行していたのが、上記の壊し合いの原因でした）。

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
