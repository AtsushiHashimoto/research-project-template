<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## オプション機能の設定

### Ollama（ローカルLLM）

Ollamaのモデル永続化は事前設定済み（`data/shared/ollama_models/`）。使用するにはDockerfileにインストールコマンドを追加：

```dockerfile
# .devcontainer/Dockerfile に追加
RUN curl -fsSL https://ollama.com/install.sh | sh
```

コンテナ再ビルド後、以下で使用可能：
```bash
ollama serve &          # サーバー起動
ollama pull llama3.2    # モデルダウンロード
ollama run llama3.2     # 実行
```

### Shared Resource Manager（worktree / devcontainer 間の排他制御）

複数 worktree・複数 devcontainer が外部リソース（ポート、GPU、ROS master 等）を
奪い合うときに使います（#52）。flock ベースで daemon 不要、**プロセスが死ねば OS が
ロックを自動解放**します（ゾンビロックが起きない）。

```bash
# ロックを取ってサーバーを起動（コマンド終了・プロセス死で自動解放）
bash scripts/resource.sh acquire review_server -- python server.py --port 5051

# 誰が持っているか確認（pid / host / worktree / 開始時刻 / コマンド）
bash scripts/resource.sh status

# holder に SIGTERM を送って解放
bash scripts/resource.sh release review_server

# 空くまで待つ / N 秒だけ待つ
bash scripts/resource.sh acquire gpu:0 --wait -- python train.py
bash scripts/resource.sh acquire gpu:0 --timeout 30 -- python train.py
```

- リソース定義は**任意**: `data/shared/resources/definitions.json`（無くても ad-hoc 名で動作）
- ロック置き場の既定は `data/shared/resources/locks/`（worktree 間で共有）
- **複数 devcontainer で共有する場合**（opt-in）: devcontainer.json に bind mount を追加すると
  `/var/resource-registry` が自動的に使われ、コンテナ間で排他が効く

  ```jsonc
  "initializeCommand": "mkdir -p ${localEnv:HOME}/.local/share/resource-registry",
  "mounts": [
    "source=${localEnv:HOME}/.local/share/resource-registry,target=/var/resource-registry,type=bind"
  ]
  ```

- 制約: **NFS 上ではロック動作が保証されない**。ロックはローカルディスクに置くこと

### Claude Code認証

認証情報はプロジェクト専用のDocker volumeで永続化。初回のみ `claude` を実行して認証。コンテナ再ビルド後も自動的に維持される。

**注意**: ホストや他のdevcontainerとは認証情報が分離されているため、各プロジェクトで初回認証が必要。
