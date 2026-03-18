# QA Check

`docs/qa/answers.jsonl` から未処理の回答を確認するスキル。

## Usage

```
/qa/check
/qa/check Q001
/qa/check --all
/qa/check Q001 --reply "フォローアップメッセージ"
```

## Parameters

- `question_id`: 特定の質問IDの回答を確認（オプション）
- `--all`: 全ての回答を表示
- `--reply "message"`: 指定した質問のスレッドにメッセージを返信

## Implementation

QAモジュールは `scripts/qa/` に配置されています。

```python
import sys
from pathlib import Path

# Add scripts/ to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "scripts"))

from qa.models import Answer, Question
from qa.store import QAStore
```

## Workflow

### 回答確認モード（デフォルト）

1. `docs/qa/questions.jsonl` から質問を読み込み
2. `docs/qa/answers.jsonl` から回答を読み込み
3. 未処理の回答（まだ作業に反映していない）を表示
4. 必要に応じて作業に反映

### スレッド返信モード（--reply）

1. `questions.jsonl` から指定した質問の `message_id` を取得
2. Slack/Discord の同じスレッドにメッセージを返信
3. 対話的なQAを継続可能

```python
# スレッド返信の実装例
import os
from dotenv import load_dotenv
from slack_sdk import WebClient

load_dotenv()
client = WebClient(token=os.environ['SLACK_BOT_TOKEN'])

# 質問の message_id を取得
store = QAStore(Path("docs/qa"))
question = store.get_question_by_id("Q001")

if question and question.message_id:
    client.chat_postMessage(
        channel=os.environ['SLACK_CHANNEL_ID'],
        thread_ts=question.message_id,
        text="フォローアップメッセージ"
    )
```

## Example Output

### 回答確認

```
新しい回答があります:

### Q001: CSV or JSON?
- 回答: JSON
- 回答者: hashimoto
- 時刻: 2026-03-18 10:30
- スレッドID: 1773809590.875909

仮決定と一致しています。追加の対応は不要です。

---

### Q002: Authentication method?
- 回答: OAuth2
- 回答者: hashimoto
- 時刻: 2026-03-18 11:00

deferred タスクでした。実装 Issue を作成しますか？
```

### スレッド返信

```
/qa/check Q001 --reply "了解しました。JSONで実装を進めます。"
```

出力:
```
✅ Q001 のスレッドに返信しました
```

## Integration with /issue/auto

`/issue/auto` の開始時に自動で `/qa/check` を実行し、
前回のセッションで回答があった質問を確認します。

## Thread Reply Examples

回答確認後にフォローアップする例:

```bash
# 回答を確認
/qa/check Q001

# 追加の質問
/qa/check Q001 --reply "ありがとうございます。JSON Schemaは必要ですか？"

# 確認メッセージ
/qa/check Q001 --reply "実装完了しました。確認をお願いします。"
```
