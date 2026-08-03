# DevContainer 自動化の仕組み

このドキュメントでは、`.devcontainer/` の設定が何をしているか、特に Claude Code の認証永続化の仕組みを解説します。

## 概要

DevContainer は以下を自動的にセットアップします：

- Claude Code + claude-auto-retry のインストール
- CPU / GPU の自動切り替え（docker-compose による構成分離）
- Git / GitHub CLI の認証引き継ぎ
- Claude Code の認証永続化（コンテナ再ビルド後もログイン不要）

## ファイル構成

```
.devcontainer/
├── Dockerfile                        # [Template] 共通イメージ（CPU/GPU対応）
├── docker-compose.yml                # [Template] 共通サービス定義
├── post-create.sh                    # [Template] 共通ライフサイクル処理（コンテナ作成後に1回）
├── post-start.sh                     # [Template] 共通ライフサイクル処理（コンテナ起動ごと）
├── cpu/
│   ├── devcontainer.json             # CPU固有設定
│   └── docker-compose.override.yml   # CPU override（BASE_IMAGE等）
└── gpu/
    ├── devcontainer.json             # GPU固有設定
    └── docker-compose.override.yml   # GPU override（nvidia, shm等）
```

**設計方針**: CPU と GPU で共通の設定は `docker-compose.yml`、`Dockerfile`、`post-create.sh`、`post-start.sh` に集約し、差分のみを各 `override.yml` と `devcontainer.json` に記述します。

### `[Template]` / `[Project]` タグ

ファイル内のコメントで設定の由来を明示しています：

- `[Template]`: テンプレート由来。`/template-sync` で自動更新可能
- `[Project]`: プロジェクト固有。同期時にスキップされる

## Dockerfile の構成

### ベースイメージ

```dockerfile
ARG BASE_IMAGE=python:3.11
FROM ${BASE_IMAGE}
```

`BASE_IMAGE` は docker-compose の override で切り替えます：
- **CPU**: `python:3.11`
- **GPU**: `nvcr.io/nvidia/pytorch:24.12-py3`

### インストールされるツール

| ツール | 用途 |
|--------|------|
| git, git-lfs | バージョン管理 |
| gh (GitHub CLI) | Issue/PR 操作 |
| Node.js 20 | Claude Code の実行環境 |
| Claude Code | AI コーディングアシスタント |
| uv | 高速 Python パッケージマネージャー |
| claude-auto-retry | Rate limit 自動再開（`post-create.sh` で npm から導入） |
| tmux | セッション管理（claude-san用） |
| jq, ripgrep, fzf | 検索・データ処理 |

### uv のインストール先

```dockerfile
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
```

`uv` はシステム共有パス `/usr/local/bin` に入れます。ここは既定の `PATH` に含まれるため、
`ENV PATH` の追記は不要です。インストーラ既定の `/root/.local/bin` に置くと、
後述の `USER vscode` 切り替え後に非 root から `/root` が読めず `uv: command not found` になります（#141）。

**既知の副作用**: `/usr/local/bin` は root 所有のため、`uv self update` は非 root では失敗します。
`sudo uv self update` を使ってください。

### `claude` の実行時オプション

`--dangerously-skip-permissions` は **Dockerfile では付与していません**。
以前あった `/etc/bash.bashrc` への alias は、claude-auto-retry が定義する `claude()`
シェル関数と競合するため廃止しました（`post-create.sh` が旧 alias の残骸を除去します）。
現在の付与箇所は `post-start.sh` の `claude()` ラッパーと `claude-san` の2つです。
セキュリティへの影響は [docs/security.md](security.md) を参照。

### CPU-only PyTorch

```dockerfile
ARG INSTALL_TORCH_CPU=false
RUN if [ "$INSTALL_TORCH_CPU" = "true" ]; then \
    pip install torch --index-url https://download.pytorch.org/whl/cpu; \
fi
```

GPU ベースイメージには PyTorch が含まれていますが、CPU イメージには含まれないため、`INSTALL_TORCH_CPU=true` で CPU 版 PyTorch をインストールします。

### 非 root ユーザー（Dockerfile 末尾の `USER`）

```dockerfile
WORKDIR /workspace
USER $USERNAME     # ARG USERNAME=vscode（上部で定義済み）
```

**コンテナの主プロセスは非 root（`vscode`）です。**

`devcontainer.json` の `remoteUser: vscode` は VS Code 経由のシェルにしか効きません。
Dockerfile に `USER` が無いと、`docker compose run` / `docker exec` を直接叩いたときに
root になり、bind mount した `/workspace`（＝ホストのリポジトリ）に
**root 所有のファイルが残ります**。Linux ホストや共同研究者の環境では、その後の
`git` 操作やファイル削除が権限エラーで止まります（macOS の Docker Desktop は
UID を写像するため症状が出にくく、気づかれにくい失敗モードです）。

`apt-get` / `npm install -g` / `pip install` は root が必要なので、
**ビルド段階は root のまま**にし、切り替えは Dockerfile の末尾でだけ行います。
devcontainer features は devcontainer CLI が後段で `USER root` を挟んで導入するため、
この変更の影響を受けません。

root が必要な操作は `sudo`（NOPASSWD、`docs/security.md` §7）で行います。

## docker-compose の構成

### 共通設定（docker-compose.yml）

```yaml
services:
  devcontainer:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
    hostname: ${DEVCONTAINER_HOSTNAME:-}
    shm_size: "8gb"
    ulimits:
      memlock: -1
      stack: 67108864
    volumes:
      - ..:/workspace:cached          # ワークスペースマウント
      - ${HOME}/.gitconfig:...        # Git 認証引き継ぎ
      - ${HOME}/.config/gh:...        # GitHub CLI 認証引き継ぎ
      - /etc/localtime:...            # タイムゾーン
```

### GPU override（gpu/docker-compose.override.yml）

```yaml
services:
  devcontainer:
    build:
      args:
        BASE_IMAGE: "nvcr.io/nvidia/pytorch:24.12-py3"
        INSTALL_TORCH_CPU: "false"
    shm_size: "64gb"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

## devcontainer.json の構成

### マウント

```jsonc
"mounts": [
  // Claude Code の設定・認証を Named Volume で永続化
  "source=claude-code-config-${localWorkspaceFolderBasename},target=/home/vscode/.claude,type=volume"
]
```

**ポイント**: Git と GitHub CLI のマウントは docker-compose.yml 側で定義。Claude Code の Named Volume はdevcontainer 変数（`${localWorkspaceFolderBasename}`）を使うため devcontainer.json 側で定義しています。

### post-create.sh

コンテナ作成後に1回だけ実行される共通処理：

```bash
# 1. Claude 設定ディレクトリの所有権修正（Named Volume は root 所有でマウントされうる）
sudo chown -R "$(id -u):$(id -g)" /home/vscode/.claude

# 2. Claude の設定ファイルシンボリックリンク
ln -sf /home/vscode/.claude/.claude.json /home/vscode/.claude.json

# 3. 決定論的 machine-id の生成
echo -n "devcontainer-${PROJECT_NAME}" | md5sum | cut -c1-32 | sudo tee /etc/machine-id > /dev/null

# 4. TZ が未設定なら /etc/timezone から /etc/profile.d/tz.sh へ書き出す
#    （claude-auto-retry がレート制限の再開時刻をパースするために必要）

# 5. 旧 Dockerfile の claude alias が残っていれば除去し、claude-auto-retry を導入
#    （alias が無い環境でも止まらないよう失敗を許容している）
sudo sed -i '/alias claude=/d' /etc/bash.bashrc 2>/dev/null || true
if ! command -v claude-auto-retry &> /dev/null; then
  sudo npm i -g claude-auto-retry
fi

# 6. claude-san のシンボリックリンク（存在するときのみ）
#    claude-san は install.sh 経由の派生プロジェクトには配布されないため、
#    ガードしないと壊れた symlink が無言で作られる
if [ -f "$(pwd)/claude-san" ]; then
  sudo ln -sf "$(pwd)/claude-san" /usr/local/bin/claude-san
fi

# 7. worktree の .git 参照を相対パス化（ホスト/コンテナ間でパスが異なるため）
#    スクリプトが無い派生プロジェクトでも止まらないようガードしている
if [ -x ./scripts/configure-worktree-paths.sh ]; then
  ./scripts/configure-worktree-paths.sh || true
fi
```

`sudo` を使う処理があるのは、`postCreateCommand` が**以前から** `vscode`（非 root）として
実行されるためです（`devcontainer.json` の `remoteUser`）。
`USER vscode` の追加（#141）はこの前提を変えていません。変わったのは
**VS Code を経由しない `docker exec` / `docker compose run` の既定ユーザー**です。

### post-start.sh

コンテナ起動ごとに実行される共通処理：

```bash
# claude-auto-retry: .bashrc に claude() シェル関数を注入
claude-auto-retry install

# --dangerously-skip-permissions を常に付与する claude() ラッパーを
# .bashrc へ追記（# claude-skip-permissions マーカー付きブロック）
```

`postCreateCommand` ではなく `postStartCommand` で行うのは、`postCreateCommand` の時点では
`updateRemoteUserUID` により `.bashrc` が上書きされる可能性があるためです。

プロジェクト固有の追加セットアップは `devcontainer.json` の `postCreateCommand` で `post-create.sh` の後に追記します：

```jsonc
// gpu/devcontainer.json の例
"postCreateCommand": "bash .devcontainer/post-create.sh ${localWorkspaceFolderBasename} && mkdir -p data/shared/ollama_models"
```

## 認証永続化のメカニズム

### なぜコンテナ再ビルド後もログインが不要なのか

Claude Code の認証は以下の2つの要素で成り立っています：

1. **認証トークン**: `/home/vscode/.claude/` 内に保存
2. **machine-id**: `/etc/machine-id` — マシンを識別する固有ID

通常、コンテナを再ビルドすると両方が失われ、再認証が必要になります。本テンプレートでは：

- **認証トークン** → Named Volume (`claude-code-config-*`) に保存。コンテナ再ビルドでも消えない
- **machine-id** → ワークスペース名から決定論的に生成。再ビルド後も同じ値になる

この2つの組み合わせにより、Claude Code はコンテナ再ビルド後も「同じマシン」と認識し、再認証をスキップします。

### Named Volume のライフサイクル

```
プロジェクト作成 → Volume 作成（初回のみ）
    ↓
コンテナ再ビルド → Volume は維持される
    ↓
プロジェクト削除 → Volume は手動で削除するまで残る
```

Volume の確認・削除：

```bash
# ホストマシンで実行
docker volume ls | grep claude-code-config
docker volume rm claude-code-config-my-project  # 削除する場合
```

### 設定ファイルのシンボリックリンク

Claude Code は設定を2箇所から読む場合があります：

- `/home/vscode/.claude/.claude.json` (Volume 内)
- `/home/vscode/.claude.json` (ホームディレクトリ直下)

`post-create.sh` でシンボリックリンクを作成し、両方が同じファイルを指すようにしています。

## GPU アクセス

### docker-compose による GPU 設定

```yaml
# gpu/docker-compose.override.yml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

### コンテナのホスト名

`hostname` は既定で**未指定（空）**です。未指定のとき Docker はホスト名に
**コンテナ ID の16進**（例: `614cfeb1a4d1`）を使います。**コンテナ名は使われません。**

複数プロジェクトのコンテナをシェルのプロンプトやログで区別したい場合は、
ホスト側で環境変数を定義してください。

```bash
# ホスト側（.zshrc 等）
export DEVCONTAINER_HOSTNAME=myproject
```

かつては `hostname: devcontainer` と固定していたため、
**複数プロジェクトのコンテナが同じホスト名になり区別できませんでした**（#122 項目 H）。

### 起動時チェック

```jsonc
// cpu/devcontainer.json
"initializeCommand": "bash scripts/ensure-host-mounts.sh || true",
"postStartCommand": "bash .devcontainer/post-start.sh",

// gpu/devcontainer.json
"initializeCommand": "bash scripts/ensure-host-mounts.sh || true; bash .devcontainer/../scripts/check-nvidia-symlinks.sh 2>/dev/null || true",
"postStartCommand": "bash .devcontainer/post-start.sh; nvidia-smi > /dev/null 2>&1 && echo '[GPU] Access OK' || echo '[GPU] WARNING: GPU access lost. Container restart required.' >&2"
```

- **`ensure-host-mounts.sh`（CPU/GPU 共通）**: bind mount 対象（`~/.gitconfig` `~/.config/gh`）が
  ホストに無いと、Docker が**ディレクトリとして自動作成**してしまい、以後ホストの git が
  `fatal: ... is a directory` で動かなくなります。コンテナ作成前に正しい種別で用意します
- **`post-start.sh` は CPU / GPU 共通**です。GPU 側は同じ `postStartCommand` に
  GPU アクセス確認を**足している**だけで、置き換えてはいません
  （置き換えると `claude()` ラッパーの注入が GPU 環境だけ失われます）
- **GPU のみ**: コンテナ起動ごとに GPU アクセスを確認。ホストの再起動等で
  GPU アクセスが失われた場合に警告を表示します

## Ollama 設定（プロジェクト固有）

Ollama を使用するプロジェクトでは、GPU の `docker-compose.override.yml` に環境変数を追加します：

```yaml
# gpu/docker-compose.override.yml に追記
environment:
  OLLAMA_MODELS: /workspace/data/shared/ollama_models
```

`devcontainer.json` の `postCreateCommand` でディレクトリ作成を追記：

```jsonc
"postCreateCommand": "bash .devcontainer/post-create.sh ${localWorkspaceFolderBasename} && mkdir -p data/shared/ollama_models"
```
