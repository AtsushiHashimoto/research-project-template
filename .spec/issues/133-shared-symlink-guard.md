# Issue #133 仕様: data/shared の symlink ガード

- 状態: approved（auto-reviewer 判断済み。C1/C2 と V8/V9 を反映。ログ: 133-auto-decisions.md）
- 出自: PR #84（downstream 由来）。symlink ガード部分のみ抽出

## 問題

`scripts/setup-worktree.sh` は `data/shared` が **symlink かどうか**（`-L`）しか見ていない。

```bash
if [[ -L "data/shared" ]]; then   # ← symlink のときだけ処理
    ...
fi
...
ln -sf "$SHARED_DATA_PATH" data/shared
```

`data/shared` が**実ディレクトリ**の場合、`ln -sf TARGET data/shared` は
リンクを**そのディレクトリの中**に作る（`data/shared/shared`）。

結果:

- worktree で `data/shared/` に保存した重要データが本体と共有されない
- **worktree 削除でそのデータが失われる**（`.gitignore` で追跡外のため git にも残らない）
- しかも `ln -sf` は成功し、成功メッセージまで出る → **silent-wrong**（R-D01 / KI-D03 型）

これは `.claude/rules/template/data-protection.md` が保証すると謳っている
「worktree 削除時もデータを保護する」機構そのものの不成立。**INV-D03 に関わる。**

## 設計

### D1: 実ディレクトリの検出と分岐

`-L` の判定の後に、**symlink でない実ディレクトリ**の分岐を追加する。

| 状態 | 動作 |
|---|---|
| symlink（壊れたものを含む） | 従来どおり（再作成の確認）。`-L` が真なのでデータ喪失は起きない |
| **実ディレクトリ・中身が空** | 削除して symlink に置き換える（情報表示） |
| **実ディレクトリ・データあり** | **リンクを作らず停止**し、移動コマンドを提示する |
| **実ファイル（C1）** | **停止**。現行は分岐が無く `ln -sf` に落ちて**ファイルが無警告で消える**（実測） |
| **読み取れない** | 停止して権限確認を促す |
| 何も無い | 従来どおり symlink を作る |

**★ C1（auto-reviewer が実測）**: 「存在するが symlink でもディレクトリでもない」行が
仕様から抜けていた。この経路が最もデータを失う（ファイルが黙って消える）。

**データがある場合に自動で移動しない。** 移動先に同名ファイルがあると壊れるため、
判断と実行はユーザーに委ねる（案内は必ず出す＝黙って進めない）。

### D1': 追跡ポリシーの修正（★ C2。これが根本原因）

**空ディレクトリの置換は例外ではなく、全新規 worktree の標準経路である。**

`.gitignore` が `data/shared/**` ＋ `!data/shared/.gitkeep` としているため
**`.gitkeep` が git 追跡下にあり**、`git worktree add` は必ず `data/shared/` を
実ディレクトリとして具現化する。つまり:

- symlink を張るには毎回このディレクトリを消すことになる
- 消すと ` D data/shared/.gitkeep` ＋ `?? data/shared` で **git が恒久的に汚れる**
- エージェントが削除をコミットして main に伝播する退行リスクがある

**追跡ポリシー自体を直す**（PR #84 の判断を採用）:

```
# 変更前
data/shared/**
!data/shared/.gitkeep

# 変更後
data/shared
```

- `.gitkeep` は**追跡から外す**（`git rm --cached`）。メインリポジトリ側の
  `data/shared` は `scripts/init-data.sh` が作るので、雛形として追跡する必要が無い
- **`data/shared/**` ではなく `data/shared` と書く。** `/**` は配下にしかマッチせず
  **パス自体にマッチしない**ため、symlink 化した `data/shared` が未追跡として露出し、
  `git add .` で**ホストの絶対パスを含む symlink がコミットされる**（PR #84 の指摘）
- `scripts/ensure-gitignore.sh` の `REQUIRED_ENTRIES`（#122 で導入した単一情報源）も
  同時に更新する。**片方だけ直すと install / sync が古いエントリを復活させる**

### D2: 旧バージョンが作った stray link の片付け

すでに壊れた状態のプロジェクトを救済する。`data/shared` が実ディレクトリで、
その中に **`readlink` が `SHARED_DATA_PATH` に一致する symlink** があれば、
旧バージョンの生成物なので削除する。削除したことは表示する。

**名前で判定しない。** 旧バグが作る名前は `shared` 固定ではなく
`basename "$SHARED_DATA_PATH"` である（auto-reviewer 指摘）。

これは D1 の「中身が空か」の判定より**前**に行う（stray link を消せば空になるケースがある）。

### D3: メッセージの多言語化

既存の `msg()` に ja / zh / en の3言語でキーを追加する（既存の作法に合わせる）。

## Fallback ホワイトリスト

なし。**データがある場合は停止する**（握り潰さない）。

## 検証チェックリスト

- [ ] V1: `data/shared` が無い状態 → 従来どおり symlink が作られる
- [ ] V2: `data/shared` が**空の実ディレクトリ** → 削除され symlink に置き換わる
- [ ] V3: `data/shared` が**データ入りの実ディレクトリ** → **symlink を作らず exit 1**、
      移動コマンドが表示される。**`data/shared/shared` が作られていないこと**を確認
- [ ] V4: 旧バージョンの `data/shared/shared`（stray link）が検出・削除される
- [ ] V5: 既存の symlink がある場合の挙動（再作成の確認）が変わっていない
- [ ] V6: **退行なし** — 旧スキル表記が 0（#117）、`setup-worktree.sh` の実行ビットが 100755（#122 N）
- [ ] V7: shellcheck 0 件、quality-check PASS
- [ ] V8: **C1** — `data/shared` が実ファイルのとき、停止し**ファイルが消えていない**
- [ ] V9: **C2** — 新規 worktree で setup を実行した後、`git status` が汚れない
      （` D data/shared/.gitkeep` や `?? data/shared` が出ない）
- [ ] V10: `.gitignore` と `ensure-gitignore.sh` の両方が更新され、
      install / sync が古いエントリを復活させない
- [ ] V11: **#108 F4 の退行なし** — `/lib/` のルート限定アンカーが保たれている
      （PR #84 はここを裸の `lib/` に戻しているので取り込まない）
