# QA Ask

質問を `docs/qa/questions.jsonl` に追記するスキル。

## Usage

```
/qa/ask
/qa/ask "CSV or JSON?"
/qa/ask --type provisional --decision JSON "Data format preference?"
/qa/ask --type deferred --stub "auth_placeholder()" "Authentication method?"
```

## Parameters

- `question`: 質問内容（必須）
- `--type`: 質問タイプ（provisional | deferred）デフォルト: provisional
- `--decision`: 仮決定（provisional の場合）
- `--stub`: スタブコード（deferred の場合）
- `--options`: 選択肢（カンマ区切り）

## Implementation

QAモジュールは `scripts/qa/` に配置されています。

```python
import sys
from pathlib import Path

# Add scripts/ to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "scripts"))

from qa.models import Question, QuestionType
from qa.store import QAStore
```

## Workflow

1. 現在のIssue番号を取得（ブランチ名から抽出）
2. 次の質問IDを生成（Q001, Q002, ...）
3. Question オブジェクトを作成
4. `docs/qa/questions.jsonl` に追記

## Example Output

```
質問を追加しました:
- ID: Q001
- Issue: #21
- Type: provisional
- Question: CSV or JSON?
- Decision: JSON

QA Bot が Slack/Discord に投稿します。
回答を待機中...
```

## 回答待機

質問投稿後、約1分間 `answers.jsonl` をポーリングして回答を待ちます。

```python
import time
import json
from pathlib import Path

def wait_for_answer(question_id: str, timeout: int = 60, interval: int = 5) -> str | None:
    """回答を待機する。タイムアウトしたらNoneを返す。"""
    answers_file = Path("docs/qa/answers.jsonl")
    start = time.time()

    while time.time() - start < timeout:
        if answers_file.exists():
            for line in answers_file.read_text().strip().split('\n'):
                if line:
                    a = json.loads(line)
                    if a['id'] == question_id:
                        return a['answer']
        time.sleep(interval)

    return None

# 質問投稿後
answer = wait_for_answer(question_id, timeout=60)
if answer:
    print(f"✅ 回答を受信: {answer}")
    # 回答に基づいて作業継続
else:
    # タイムアウト: 仮決定を採用してスレッドに通知
    if question.decision:
        notify_decision(question)
        print(f"⏳ タイムアウト。仮決定「{question.decision}」で続行します。")
    else:
        print("⏳ タイムアウト。後で /qa/check で確認してください。")
```

## タイムアウト時の仮決定通知

回答がない場合、仮決定（provisional の decision）をスレッドに投稿して作業を継続します。

```python
import os
from slack_sdk import WebClient
from dotenv import load_dotenv

def notify_decision(question: Question) -> None:
    """仮決定をSlackスレッドに投稿"""
    load_dotenv()
    client = WebClient(token=os.environ['SLACK_BOT_TOKEN'])

    # questions.jsonl から message_id を取得
    store = QAStore(Path("docs/qa"))
    q = store.get_question_by_id(question.id)

    if q and q.message_id and question.decision:
        client.chat_postMessage(
            channel=os.environ['SLACK_CHANNEL_ID'],
            thread_ts=q.message_id,
            text=f"⏳ 回答待機がタイムアウトしました。仮決定「{question.decision}」で作業を続行します。"
        )
```

これにより:
- 回答があれば採用して継続
- なければ仮決定を採用し、スレッドに通知して継続
- 後から異議があれば `/qa/check` で確認可能
