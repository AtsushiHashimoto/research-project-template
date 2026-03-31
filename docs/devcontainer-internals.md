# DevContainer 自動化の仕組み

このドキュメントでは、`.devcontainer/` の設定が何をしているか、特に Claude Code の認証永続化の仕組みを解説します。

## 概要

DevContainer は以下を自動的にセットアップします：

- Claude Code + autoclaude のインストール
- CPU / GPU の自動切り替え（docker-compose による構成分離）
- Git / GitHub CLI の認証引き継ぎ
- Claude Code の認証永続化（コンテナ再ビルド後もログイン不要）

## ファイル構成

```
.devcontainer/
├── Dockerfile                        # [Template] 共通イメージ（CPU/GPU対応）
├── docker-compose.yml                # [Template] 共通サービス定義
├── post-create.sh                    # [Template] 共通ライフサイクル処理
├── cpu/
│   ├── devcontainer.json             # CPU固有設定
│   └── docker-compose.override.yml   # CPU override（BASE_IMAGE等）
└── gpu/
    ├── devcontainer.json             # GPU固有設定
    └── docker-compose.override.yml   # GPU override（nvidia, shm等）
```

**設計方針**: CPU と GPU で共通の設定は `docker-compose.yml`、`Dockerfile`、`post-create.sh` に集約し、差分のみを各 `override.yml` と `devcontainer.json` に記述します。

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
| autoclaude | Rate limit 自動再開（マルチアーキテクチャ対応） |
| tmux | セッション管理（claude-san用） |
| jq, ripgrep, fzf | 検索・データ処理 |

### claude の alias

```dockerfile
RUN echo 'alias claude="claude --dangerously-skip-permissions"' >> /etc/bash.bashrc
```

`claude` コマンド実行時に自動的に `--dangerously-skip-permissions` を付与。セキュリティへの影響は [docs/security.md](security.md) を参照。

### CPU-only PyTorch

```dockerfile
ARG INSTALL_TORCH_CPU=false
RUN if [ "$INSTALL_TORCH_CPU" = "true" ]; then \
    pip install torch --index-url https://download.pytorch.org/whl/cpu; \
fi
```

GPU ベースイメージには PyTorch が含まれていますが、CPU イメージには含まれないため、`INSTALL_TORCH_CPU=true` で CPU 版 PyTorch をインストールします。

## docker-compose の構成

### 共通設定（docker-compose.yml）

```yaml
services:
  devcontainer:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
    hostname: devcontainer
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

コンテナ作成後に実行される共通処理：

```bash
# 1. Claude 設定ディレクトリの所有権修正
sudo chown -R "$(id -u):$(id -g)" /home/vscode/.claude

# 2. Claude の設定ファイルシンボリックリンク
ln -sf /home/vscode/.claude/.claude.json /home/vscode/.claude.json

# 3. 決定論的 machine-id の生成
echo -n "devcontainer-${PROJECT_NAME}" | md5sum | cut -c1-32 | sudo tee /etc/machine-id > /dev/null

# 4. claude-san のシンボリックリンク
sudo ln -sf "$(pwd)/claude-san" /usr/local/bin/claude-san
```

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

### 起動時チェック（GPU のみ）

```jsonc
// gpu/devcontainer.json
"initializeCommand": "bash .devcontainer/../scripts/check-nvidia-symlinks.sh 2>/dev/null || true",
"postStartCommand": "nvidia-smi > /dev/null 2>&1 && echo '[GPU] Access OK' || echo '[GPU] WARNING: GPU access lost.'"
```

コンテナ起動ごとに GPU アクセスを確認。ホストの再起動等で GPU アクセスが失われた場合に警告を表示します。

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
