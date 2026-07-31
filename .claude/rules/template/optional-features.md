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

### Claude Code認証

認証情報はプロジェクト専用のDocker volumeで永続化。初回のみ `claude` を実行して認証。コンテナ再ビルド後も自動的に維持される。

**注意**: ホストや他のdevcontainerとは認証情報が分離されているため、各プロジェクトで初回認証が必要。
