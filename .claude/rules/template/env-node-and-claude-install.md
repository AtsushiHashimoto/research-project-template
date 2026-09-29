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

### 既存プロジェクトの移行手順（migration guide）

このルールを `/template-sync` で受け取ったプロジェクトは、一度だけ以下を実施する。
**ファイル同期では配れないランタイム操作**なので、各マシンで手動実行する。

1. **Claude Code を native build へ。** `claude install latest` → `claude --version` が 2.1.280 以上、
   `which claude` が `~/.local/bin/claude` を指すことを確認。**その後 `claude` を再起動する**
   （起動中のセッションは古いプロセスのまま）。
2. **モデルを選ぶ。** 再起動後 `/model` で Opus 5.5 等を選ぶ（既定として保存される）。
   `~/.claude/settings.json` の `"model"` に古い ID が固定されていると、それに張り付くので確認する。
3. **モデルポリシー。** `.claude/model-policy.json` の `planning` / `abstract-review` の primary が
   `opus`（既定から fable を廃止）。`bash scripts/resolve-model.sh --list` で確認する。
4. **npm 版ツールを使う場合のみ Node 22 化。** 稼働中コンテナなら
   `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs`。

### 既知の制約（devcontainer 側は未対応）

**テンプレート同梱の `.devcontainer/` はまだこのルールに追従していない**（Node 20 の NodeSource と
`npm install -g @anthropic-ai/claude-code` のまま）。追従は別の変更で行う予定。それまでは以下に注意する:

- **rebuild で native build が消える。** 永続化されるのは `~/.claude` の volume だけで、`~/.local/` は消える。
  rebuild 後は手順 1 をやり直す。
- **PATH 順。** Dockerfile が `ENV PATH="/usr/bin:${PATH}"` で `/usr/bin` を先頭にしているため、
  `~/.local/bin` が前に来るのは `~/.profile` を読むログインシェルだけ。非ログインシェルや exec 経由では
  npm 版の `/usr/bin/claude` が選ばれ得る。`which claude` とバージョンを必ず確認する。
- 旧 npm 版を消すなら `sudo npm rm -g @anthropic-ai/claude-code`。
- Node のバージョンは**メジャーのみ固定**する（マイナー/パッチは固定しない）。
