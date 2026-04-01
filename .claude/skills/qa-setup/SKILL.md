# QA System Setup

QAシステム（Slack/Discord連携）のセットアップを対話的にガイドします。

## Usage

```
/qa/setup           # 対話的セットアップを開始
/qa/setup slack     # Slackセットアップのみ
/qa/setup discord   # Discordセットアップのみ
```

## Prerequisites

- GitHub リポジトリへのアクセス
- Slack workspace の管理者権限、または Discord サーバーの管理者権限

## Documentation

詳細なセットアップ手順とトラブルシューティングは `docs/qa/SETUP.md` を参照。

セットアップ中に問題が発生した場合:
1. `docs/qa/SETUP.md` の「トラブルシューティング」セクションを確認
2. 特に `missing_scope` エラーの場合、パブリック/プライベートチャンネルで必要なスコープが異なる

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

```yaml
# QA System Configuration
platform: slack  # or discord

# File paths
questions_file: docs/qa/questions.jsonl
answers_file: docs/qa/answers.jsonl

# Watcher settings
watcher:
  use_inotify: true
  poll_interval: 5  # seconds (fallback)

# Notification settings
notification:
  mention_on_question: true
  thread_replies: true
```

### Step 5: ディレクトリ構造作成

```bash
mkdir -p docs/qa
touch docs/qa/questions.jsonl
touch docs/qa/answers.jsonl
```

### Step 6: 依存関係インストール

```bash
pip install -r scripts/qa/requirements.txt
```

### Step 7: 接続テスト

```bash
# テストメッセージを送信
python -c "
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
            issue_id=0,
            question_type=QuestionType.PROVISIONAL,
            question='セットアップテスト - このメッセージが見えれば成功です',
            context='QA System Setup Test',
            provisional_answer='テスト完了'
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
│   - docs/qa/questions.jsonl                                 │
│   - docs/qa/answers.jsonl                                   │
│                                                             │
│ 使い方:                                                     │
│   /qa/ask "質問内容"  - 質問を投稿                          │
│   /qa/check           - 回答を確認                          │
│                                                             │
│ Bot起動:                                                    │
│   python scripts/qa_bot.py                                  │
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
| `.claude/qa-config.yaml` | QA設定 |
| `docs/qa/questions.jsonl` | 質問データ |
| `docs/qa/answers.jsonl` | 回答データ |

## Related Skills

| スキル | 用途 |
|-------|------|
| `/qa/ask` | 質問を投稿 |
| `/qa/check` | 回答を確認 |
