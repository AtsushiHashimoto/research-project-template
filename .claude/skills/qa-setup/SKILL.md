---
description: QAシステム（Slack/Discord連携）のセットアップを対話的にガイドする
---

# QA System Setup

QAシステム（Slack/Discord連携）のセットアップを対話的にガイドします。

## Usage

```
/qa-setup           # 対話的セットアップを開始
/qa-setup slack     # Slackセットアップのみ
/qa-setup discord   # Discordセットアップのみ
```

## Prerequisites

- GitHub リポジトリへのアクセス
- Slack workspace の管理者権限、または Discord サーバーの管理者権限

## Documentation

**手順とトラブルシューティングはこのファイルに集約されています（単一情報源）。**
別ファイルの `SETUP.md` は作りません（同じ手順が2箇所に分かれると必ず食い違うため）。

セットアップ中に問題が発生した場合は、下の「Error Handling」節を参照してください。
特に `missing_scope` エラーの場合、パブリックチャンネル（`channels:history`）と
プライベートチャンネル（`groups:history`）で必要なスコープが異なります。

## Workflow

### Step 1: プラットフォーム選択

引数がない場合、ユーザーに選択を求める：

```
AskUserQuestion(questions=[{
  "question": "どのプラットフォームを使用しますか？",
  "header": "Platform",
  "options": [
    {"label": "Slack (Recommended)", "description": "Socket Modeで無料利用可能"},
    {"label": "Discord", "description": "Discord Botで連携"}
  ],
  "multiSelect": false
}])
```

### Step 2: アプリ作成ガイド

#### Slack の場合

1. **Slack App 作成手順を表示**:

```markdown
## Slack App 作成手順

1. https://api.slack.com/apps にアクセス
2. "Create New App" → "From scratch" を選択
3. App名を入力（例: `QA Bot`）、Workspaceを選択

### Socket Mode 有効化
4. 左メニュー "Socket Mode" → "Enable Socket Mode" をON
5. App-Level Token を生成:
   - Token Name: `qa-bot-token`
   - Scope: `connections:write`
   - 生成された `xapp-...` トークンをコピー

### Bot Token Scopes 設定
6. 左メニュー "OAuth & Permissions" → "Bot Token Scopes" に追加:
   - `chat:write` - メッセージ送信
   - `channels:history` - チャンネル履歴読み取り
   - `groups:history` - プライベートチャンネル履歴

### Event Subscriptions 設定
7. 左メニュー "Event Subscriptions" → Enable Events をON
8. "Subscribe to bot events" に追加:
   - `message.channels`
   - `message.groups`

### アプリをインストール
9. 左メニュー "Install App" → "Install to Workspace"
10. `xoxb-...` Bot User OAuth Token をコピー

### チャンネル設定
11. Slack で QA 用チャンネルを作成（例: `#qa-bot`）
12. チャンネルにアプリを招待: `/invite @QA Bot`
13. チャンネルIDを取得（チャンネル名を右クリック → "Copy link" → URLの最後の部分）
```

2. **トークン入力を求める**:

```
AskUserQuestion(questions=[
  {
    "question": "App-Level Token (xapp-...) を入力してください",
    "header": "App Token",
    "options": [
      {"label": "入力する", "description": "トークンを入力します"}
    ],
    "multiSelect": false
  }
])
```

ユーザーが「Other」を選択してトークンを入力。同様に Bot Token と Channel ID も取得。

#### Discord の場合

1. **Discord App 作成手順を表示**:

```markdown
## Discord Bot 作成手順

1. https://discord.com/developers/applications にアクセス
2. "New Application" をクリック
3. アプリ名を入力（例: `QA Bot`）

### Bot 設定
4. 左メニュー "Bot" → "Add Bot"
5. "Reset Token" でトークンを生成、コピー
6. "MESSAGE CONTENT INTENT" を有効化

### サーバーに招待
7. 左メニュー "OAuth2" → "URL Generator"
8. Scopes: `bot`
9. Bot Permissions: `Send Messages`, `Read Message History`
10. 生成されたURLでサーバーに招待

### チャンネルID取得
11. Discord設定 → 詳細設定 → 開発者モードをON
12. チャンネルを右クリック → "IDをコピー"
```

2. **トークン入力を求める**（Slackと同様）

### Step 3: 環境変数設定

取得したトークンを `.env` ファイルに追記:

```bash
# .env ファイルが存在するか確認
if [ ! -f .env ]; then
  touch .env
  echo "# QA Bot Configuration" >> .env
fi

# Slack の場合
echo "" >> .env
echo "# QA Bot - Slack" >> .env
echo "SLACK_APP_TOKEN=xapp-..." >> .env
echo "SLACK_BOT_TOKEN=xoxb-..." >> .env
echo "SLACK_CHANNEL_ID=C..." >> .env

# Discord の場合
echo "" >> .env
echo "# QA Bot - Discord" >> .env
echo "DISCORD_BOT_TOKEN=..." >> .env
echo "DISCORD_CHANNEL_ID=..." >> .env
```

**重要**: `.env` は `.gitignore` に含まれていることを確認。

### Step 4: 設定ファイル作成

`.claude/qa-config.yaml` を作成:

**キー名は `scripts/qa/config.py` の `QAConfig` と一致させること。**
知らないキーを書いても黙って無視される（設定したつもりが効かない）ので、
下のキー以外は追加しないでください。

```yaml
# QA System Configuration（キーの定義: scripts/qa/config.py の QAConfig）
notifier: slack        # slack | discord

# 質問・回答ファイルの置き場所。
# 既定は .dev/qa（省略可）。内部開発メモは .dev/ に置く規約に従う
qa_dir: .dev/qa

# Issue へのリンクを通知に含めるためのリポジトリ URL（任意）
github_repo: https://github.com/<owner>/<repo>

slack:
  channel: C0123456789   # チャンネル ID
# discord:
#   channel_id: 123456789012345678
```

### Step 5: ディレクトリ構造作成

```bash
# 参照先は scripts/qa/qa-dir.sh が解決する（qa-config.yaml の qa_dir → 既定 .dev/qa）
QA_DIR=$(bash scripts/qa/qa-dir.sh)
mkdir -p "$QA_DIR"
touch "$QA_DIR/questions.jsonl"
touch "$QA_DIR/answers.jsonl"
echo "QA データ: $QA_DIR"
```

**旧バージョンから移行する場合**: QA データは以前 `docs/qa/` に置かれていました。
`docs/qa/*.jsonl` が残っていると `qa-dir.sh` が移行を案内します（自動では移動しません）。

```bash
git mv docs/qa/questions.jsonl docs/qa/answers.jsonl "$QA_DIR"/
```

### Step 6: 依存関係インストール

QA モジュールは追加パッケージを必要とします（テンプレート本体は依存を持たないため、
requirements ファイルは置かず、使うときに入れる方式です）。

```bash
# 共通
pip install pydantic pyyaml python-dotenv

# Slack を使う場合
pip install slack-bolt slack-sdk

# Discord を使う場合
pip install discord.py

# 任意: ファイル監視を inotify にする（未導入ならポーリングで動作）
pip install inotify
```

`pyproject.toml` を持つプロジェクトでは、上記を依存に追加して `uv sync` でも構いません。

### Step 7: 接続テスト

```bash
# テストメッセージを送信
# フィールド名は scripts/qa/models.py の Question と一致させること
PYTHONPATH=scripts python -c "
import asyncio
from qa.notifiers.slack import SlackNotifier  # or discord
from qa.models import Question, QuestionType

async def test():
    notifier = SlackNotifier()
    if await notifier.health_check():
        print('✅ 接続成功')
        # テスト質問を送信
        q = Question(
            id='test-001',
            issue=0,
            type=QuestionType.PROVISIONAL,
            question='セットアップテスト - このメッセージが見えれば成功です',
            decision='テスト完了'
        )
        await notifier.post_question(q)
        print('✅ テストメッセージ送信完了')
    else:
        print('❌ 接続失敗 - トークンを確認してください')

asyncio.run(test())
"
```

### Step 8: 完了メッセージ

```
┌─────────────────────────────────────────────────────────────┐
│ ✅ QA System セットアップ完了                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 設定ファイル:                                               │
│   - .env (トークン)                                         │
│   - .claude/qa-config.yaml (設定)                           │
│                                                             │
│ データファイル:                                             │
│   - .dev/qa/questions.jsonl                                 │
│   - .dev/qa/answers.jsonl                                   │
│                                                             │
│ 使い方:                                                     │
│   /qa-ask "質問内容"  - 質問を投稿                          │
│   /qa-check           - 回答を確認                          │
│                                                             │
│ Bot起動（起動経路はこれ1つ）:                               │
│   bash scripts/qa/start-bot.sh                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Error Handling

### トークンが無効な場合

```
❌ エラー: トークンが無効です

考えられる原因:
1. トークンのコピーミス（前後の空白など）
2. Socket Mode が有効になっていない（Slack）
3. Bot Permissions が不足している

再度トークンを入力しますか？
[はい] [いいえ、キャンセル]
```

### チャンネルにアクセスできない場合

```
❌ エラー: チャンネルにアクセスできません

考えられる原因:
1. チャンネルIDが間違っている
2. Botがチャンネルに招待されていない
3. 必要な権限が不足している

対処方法:
- Slack: /invite @BotName でチャンネルに招待
- Discord: Botにチャンネルの閲覧権限を付与
```

## Files Created

| ファイル | 用途 |
|---------|------|
| `.env` | トークン（gitignore対象） |
| `.claude/qa-config.yaml` | QA設定（キーの定義は `scripts/qa/config.py`） |
| `.dev/qa/questions.jsonl` | 質問データ（既定パス。`qa_dir` で変更可） |
| `.dev/qa/answers.jsonl` | 回答データ（既定パス。`qa_dir` で変更可） |

## Bot の起動

**起動経路は `scripts/qa/start-bot.sh` に一本化されています。**
`.env` とトークンが揃っていればバックグラウンドで起動し、
揃っていなければ理由を表示して何もせず終了します。

```bash
bash scripts/qa/start-bot.sh          # 起動（ログ: data/local/qa-bot.log）
pgrep -fa "python.*qa"                # 起動確認
```

直接起動したい場合は `PYTHONPATH=scripts python -m qa` ですが、
二重起動の検出やログ出力が無いため、通常は上のスクリプトを使ってください。

## Related Skills

| スキル | 用途 |
|-------|------|
| `/qa-ask` | 質問を投稿 |
| `/qa-check` | 回答を確認 |
