---
paths:
  - ".devcontainer/**"
  - "scripts/voice/**"
  - "scripts/resource.sh"
  - "data/shared/resources/**"
---
<!-- [Template] research-project-template 由来。プロジェクト固有の記述は AGENTS.md に書くこと -->

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

### Claude Code の voice dictation（`/voice`。opt-in）

Claude Code の voice dictation は手元のマイクを前提にしていて、devcontainer の中ではそのままでは動かない
（公式には非対応）。手元の PC で録ったマイクの音を port forward 越しに送り、コンテナの中の仮想マイクに流して使う。
以下、手元の PC で音を送るコマンドを**送信側**、コンテナで受ける `scripts/voice/recv.py` を**受信側**と呼ぶ。

```
手元の PC: マイク → 送信側 → 127.0.0.1:9257 → VS Code の port forward
  → コンテナ: 受信側 → PulseAudio の null sink → Claude Code の録音
```

**有効にする**: `.devcontainer/options.env` に `CLAUDE_VOICE=true` を書いて Rebuild Container する。
`install.sh` が init 時に聞いて書く（`curl … | bash` のように対話できない実行では聞かれないので、手で書く）。
ファイルが無いか `false` なら何も入らない。`options.env` はコミットする（プロジェクトの全員の image に効く選択）。
作り直さずに試すなら `sudo bash .devcontainer/install-voice.sh && bash scripts/voice/start.sh`。

**既定で入れない理由**（選ぶ前に読む）:

- image が約 150 MB 大きくなり、起動のたびに PulseAudio と受信側が常駐する
- **送信側を動かしている間、手元のマイクの音がコンテナに流れ続ける。** コンテナの中のどのプロセス
  （エージェントが実行するコマンドを含む）も、その音を録れる
- 受信側に認証は無い。コンテナの中のプロセスと、手元の PC の他のプロセスは、同じ番号に音を送り込める

**使う**:

1. Claude Code で `/voice` を実行する（初回だけ。英語以外は `/config` で言語を選ぶ）
2. VS Code の「ポート」パネルに 9257 が無ければ足す
3. 手元の PC で送信側を動かす。macOS は `brew install sox` のうえで:

   ```bash
   sox -q -d -t raw -r 16000 -c 1 -b 16 -e signed - | nc 127.0.0.1 9257
   ```

   OS の既定の入力を録る。初回はターミナルにマイクの権限を求められる（macOS: システム設定 → プライバシーとセキュリティ → マイク）。
   Linux・Windows も、既定の入力を **s16le / 16 kHz / mono** の raw で同じ番号へ送ればよい（未検証）
4. Claude Code で Space を押している間に話す。音は約 1.5 秒遅れて届くので、
   話し終えてから 2 秒ほど長めに押し続ける（遅れは受信側の環境変数 `CLAUDE_VOICE_LATENCY_MS` で変えられる）
5. **使い終わったら送信側を Ctrl-C で止める**（止めれば音は流れない）

**うまく録れないとき**は `/tmp/claude-voice/recv.log` を見る。接続中は 10 秒ごとに「届いた音の秒数 / 経過秒」が出る（ほぼ同じなら正常）。

| 症状 | 原因 |
|---|---|
| `接続` の行が無い | port forward が無いか、送信側が動いていない |
| `拒否` の行が出る | 送信側を 2 つ動かしている（受けるのは 1 本だけ）。片方を止める |
| 届いた音の秒数が経過秒の半分ほど | 送信側がマイクの音を取りこぼしている。macOS の `ffmpeg -f avfoundation` で起きた（`sox` では起きない） |
| 秒数は合うのに認識されない | 送信側が別の入力（仮想デバイス等）を録っていて無音。OS の既定の入力とマイクの権限を確かめる。コンテナで `arecord -d 3 /tmp/t.wav` を録って聞くと切り分けられる |
| `流し先を起動できない`、または log が無い | 受信側か PulseAudio が動いていない。`bash scripts/voice/start.sh` を実行し、出たエラーを読む |

コンテナを起動するたびに `post-start.sh` が受信側を起動する。

### Claude Code認証

認証情報はプロジェクト専用のDocker volumeで永続化。初回のみ `claude` を実行して認証。コンテナ再ビルド後も自動的に維持される。

**注意**: ホストや他のdevcontainerとは認証情報が分離されているため、各プロジェクトで初回認証が必要。
