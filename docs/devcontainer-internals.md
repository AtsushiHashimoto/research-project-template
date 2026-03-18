# DevContainer 自動化の仕組み

このドキュメントでは、`.devcontainer/` の設定が何をしているか、特に Claude Code の認証永続化の仕組みを解説します。

## 概要

DevContainer は以下を自動的にセットアップします：

- Claude Code + autoclaude のインストール
- GPU アクセスの設定
- Git / GitHub CLI の認証引き継ぎ
- Claude Code の認証永続化（コンテナ再ビルド後もログイン不要）
- Ollama のモデル永続化

## Dockerfile の構成

### ベースイメージ

```dockerfile
FROM nvcr.io/nvidia/pytorch:24.12-py3
```

NVIDIA PyTorch コンテナをベースに使用。GPU 対応済み。CPU のみの場合は `python:3.11-slim` に変更可能。

### インストールされるツール

| ツール | 用途 |
|--------|------|
| git, git-lfs | バージョン管理 |
| gh (GitHub CLI) | Issue/PR 操作 |
| Node.js 20 | Claude Code の実行環境 |
| Claude Code | AI コーディングアシスタント |
| autoclaude | Rate limit 自動再開 |
| tmux | セッション管理（claude-san用） |
| jq, ripgrep, fzf | 検索・データ処理 |

### claude の alias

```dockerfile
RUN echo 'alias claude="claude --dangerously-skip-permissions"' >> /etc/bash.bashrc
```

`claude` コマンド実行時に自動的に `--dangerously-skip-permissions` を付与。セキュリティへの影響は [docs/security.md](security.md) を参照。

## devcontainer.json の構成

### マウント

```jsonc
"mounts": [
  // 1. ホストの Git 設定を引き継ぎ
  "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind",

  // 2. ホストの GitHub CLI 認証を引き継ぎ
  "source=${localEnv:HOME}/.config/gh,target=/home/vscode/.config/gh,type=bind",

  // 3. Claude Code の設定・認証を Named Volume で永続化
  "source=claude-code-config-${localWorkspaceFolderBasename},target=/home/vscode/.claude,type=volume"
]
```

**ポイント**: Git と GitHub CLI はホストの認証をそのまま使用。Claude Code は **プロジェクト専用の Named Volume** に保存されるため、コンテナ再ビルド後も認証が維持されます。

### postCreateCommand

コンテナ作成後に実行される一連の処理：

```bash
# 1. Claude 設定ディレクトリの所有権修正
sudo chown -R $(id -u):$(id -g) /home/vscode/.claude

# 2. Claude の設定ファイルシンボリックリンク
ln -sf /home/vscode/.claude/.claude.json /home/vscode/.claude.json

# 3. 決定論的 machine-id の生成
echo -n 'devcontainer-${localWorkspaceFolderBasename}' | md5sum | cut -c1-32 | sudo tee /etc/machine-id > /dev/null

# 4. Ollama モデルディレクトリの作成
mkdir -p "/workspaces/${localWorkspaceFolderBasename}/data/shared/ollama_models"

# 5. claude-san のシンボリックリンク
sudo ln -sf "/workspaces/${localWorkspaceFolderBasename}/claude-san" /usr/local/bin/claude-san
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

`postCreateCommand` でシンボリックリンクを作成し、両方が同じファイルを指すようにしています。

## GPU アクセス

### 起動時の設定

```jsonc
"runArgs": [
  "--gpus=all",           // 全GPUをコンテナに公開
  "--shm-size=64gb",      // 共有メモリ（DataLoader等で使用）
  "--ulimit", "memlock=-1" // メモリロック制限なし
]
```

### 起動時チェック

```jsonc
"postStartCommand": "nvidia-smi > /dev/null 2>&1 && echo '[GPU] Access OK' || echo '[GPU] WARNING: GPU access lost.'"
```

コンテナ起動ごとに GPU アクセスを確認。ホストの再起動等で GPU アクセスが失われた場合に警告を表示します。

## Ollama 設定

### モデルの永続化

```jsonc
"containerEnv": {
  "OLLAMA_MODELS": "/workspaces/${localWorkspaceFolderBasename}/data/shared/ollama_models"
}
```

Ollama のモデルデータをプロジェクトの `data/shared/ollama_models/` に保存。Worktree 間で共有され、コンテナ再ビルド後も維持されます。

### Ollama の有効化

デフォルトではモデルディレクトリのみ設定済み。Ollama 本体を使用するには Dockerfile に追加：

```dockerfile
RUN curl -fsSL https://ollama.com/install.sh | sh
```
