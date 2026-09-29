## 実行環境要件: Claude Code のインストールと Node

### 要件

- **Claude Code ≥ 2.1.280**。Opus 5 系モデル（`claude-opus-5` / `claude-opus-5-5`）は、これより古いクライアントでは
  モデル一覧に**出てこない**（エラーにならず単に見えないので、「モデルが存在しない」と誤認しやすい）。
- **Claude Code は native build（`claude install`）で入れる。** グローバル npm（`npm i -g`）に依存しない。
  native build は Node に依存しない単体の実行ファイル。
- **Node.js ≥ 22**。これは Claude Code 本体（native build）の要件ではなく、**npm 版 claude-code**
  （`engines.node >=22`）や、post-create 等で npm から入れるツール向けの要件。npm 版を入れる環境で
  Node 20 のままだと `EBADENGINE` 警告が出て動作が保証されない。

### なぜ global npm を避けるか

`npm i -g` は npm の global prefix（多くの環境で `/usr` 配下＝root 所有）に書き込む。実行ユーザーが
書けないと **auto-update が `no write permission to npm prefix` で失敗し続ける**。native build は
ユーザー書き込み可能な場所（`~/.local/bin/claude` → `~/.local/share/claude/versions/<ver>`）に入るため、
**auto-update が sudo/root 不要で通る**。

```bash
claude install latest      # native build を導入。★ stable ではなく latest（下記）
claude --version           # 2.1.280 以上であることを確認
which claude               # ~/.local/bin/claude を指すこと（下記「PATH 順」参照）
```

**★ `claude install stable` では足りないことがある。** stable チャネルは latest より遅れており、
2.1.280 未満（例: 2.1.277）が入って Opus 5 系が見えないままになる。**必ずバージョンを確認する。**
auto-update が追うチャネルは `~/.claude/settings.json` の `autoUpdatesChannel`（`"latest"` / `"stable"`）で決まる。

### devcontainer の追従状況

テンプレート同梱の `.devcontainer/` は本ルールに**追従済み**。

- **Node 22**: Dockerfile が NodeSource の `setup_22.x` で入れる（**メジャーのみ固定**。マイナー/パッチは
  固定しない）。セットアップスクリプトはファイルに落としてから実行し、入った Node のメジャー版が 22 以上で
  あることをビルド中に確かめる（取得失敗で黙ってディストリ版の古い nodejs に降格させないため）。
  Node が要るのは post-create で `npm i -g` する claude-auto-retry だけ。
- **native build**: `post-create.sh` が `.devcontainer/install-claude-native.sh` を**毎回**呼ぶ。
  `~/.local/bin/claude` が実行可能で下限（2.1.280）以上なら導入を省き（冪等）、無い・壊れている・下限未満なら
  `latest` チャネルで入れ直す。`~/.local/` は永続化されず rebuild で消えるが、post-create が入れ直すので
  **rebuild 後の手作業は不要**。下限とチャネルはこのスクリプトの変数 1 か所にだけ書いてある。
- **古い launcher の退避と復元**: 公式インストーラは自分が作ったと判断できない既存の launcher を置き換えない
  （壊れたリンクでは失敗し、通常ファイルでは成功と表示して置き換えない）。そこで導入前に既存の launcher を
  退避し、インストーラが失敗した・launcher を作らなかった場合は元に戻して FAIL にする（インストーラの取得に
  失敗したときは既存の launcher に触れない）。
- **PATH**: Dockerfile の `ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"` で、ログイン／非ログインを問わず
  `~/.local/bin` が `/usr/bin` より前に来る。以前あった `ENV PATH="/usr/bin:${PATH}"` と
  `npm install -g @anthropic-ai/claude-code` は削除した。
- **失敗の扱い**: 導入に失敗しても post-create は後続の処理を続け、最後にまとめを出して**非ゼロで終了**する
  （握りつぶさない）。手動の再実行は `bash .devcontainer/install-claude-native.sh`。
- 回帰テストは `tests/test_install_claude_native.sh`（スタブ curl と一時 HOME で動き、ネットワーク不要）で、
  `scripts/quality-check.sh` から呼ばれる。

### 既存プロジェクトの移行手順（migration guide）

このルールを `/template-sync` で受け取ったプロジェクトは、一度だけ以下を実施する。

1. **コンテナを rebuild する。** `.devcontainer/` の更新（Node 22・native build の導入・PATH）は rebuild で効く。
   rebuild 後に `claude --version` が 2.1.280 以上、`which claude` が `~/.local/bin/claude` を指すことを確認する。
   post-create のログに `[post-create:claude] ok (<版> >= 2.1.280)` が出ていること。
   `.devcontainer/` をプロジェクトで改変している場合は、Dockerfile の Node／PATH の箇所と post-create.sh の
   claude 導入の呼び出しが取り込まれているかを先に確かめる。
2. **モデルを選ぶ。** 起動後 `/model` で Opus 5.5 等を選ぶ（既定として保存される）。
   `~/.claude/settings.json` の `"model"` に古い ID が固定されていると、それに張り付くので確認する。
3. **モデルポリシー。** `.claude/model-policy.json` の `planning` / `abstract-review` の primary が
   `opus`（既定から fable を廃止）。`bash scripts/resolve-model.sh --list` で確認する。

**rebuild できるまでの暫定措置**（稼働中のコンテナで今すぐ Opus 5 系を使いたい場合）:

- `claude install latest` で native build を入れ、`claude --version` と `which claude` を確認してから
  **`claude` を再起動する**（起動中のセッションは古いプロセスのまま）。
- 旧 npm 版が残っていて先に解決される場合は `sudo npm -g uninstall @anthropic-ai/claude-code` で消す
  （古い Dockerfile は `/usr/bin` を PATH の先頭に置くため、非ログインシェルでは npm 版が選ばれ得る）。
- この措置で入れた native build は rebuild で消えるが、rebuild 後は post-create が入れ直す。

### 残る制約

- **devcontainer CLI（VS Code 等）を通さないビルド**: Node は Dockerfile で入る（NodeSource）が、claude の導入は
  post-create に依存する。`docker build` / `docker compose` だけで起動したコンテナには claude が入らないので、
  `bash .devcontainer/install-claude-native.sh` を手で実行する。
- **post-create 時に `claude.ai` への接続が要る。** 取得に失敗すると `[post-create:claude] FAIL (download: …)` を
  出して post-create が非ゼロで終わり、**postStartCommand も走らない**（claude-auto-retry のラッパーが入らない）。
  接続を回復してから `bash .devcontainer/install-claude-native.sh`（post-create 全体をやり直すなら
  `bash .devcontainer/post-create.sh <name>` の後に `bash .devcontainer/post-start.sh`）を実行する。
- **`~/.local/bin` が PATH の先頭に来る**ので、`pip install --user` が入れたスクリプトが同名のシステムのコマンドより
  優先される。
- **PAM 経由のシェル**（`su -`、`sudo -i` 等）の PATH は `/etc/environment` 由来で、Dockerfile の ENV がどう
  反映されるかはコンテナの作り方に依存する。この経路では `which claude` を確認する。
- **自動更新**: インストーラは `~/.claude.json` に `autoUpdates: false` を書くことがあるが、native 版はこれを
  無視して自動更新が有効になる（`autoUpdatesProtectedForNative`）。`claude doctor` が `Auto-updates: enabled`・
  `Auto-update channel: latest` を示すこと、非 root・sudo なしの `claude update` で `~/.local` 内の版が入れ替わる
  ことを確認済み（セッション中のバックグラウンド更新そのものは同じ書き込み先を使う）。
