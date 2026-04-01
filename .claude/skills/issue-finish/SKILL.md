---
description: Finish task with quality review by invoking commit/merge workflow (タスク完了)
---

# Finish Task（タスク完了）

タスクを完了します。`/commit/merge` のエイリアスです。

## 用途

**タスクが完全に完了した時に使用**します。

以下を実行します：
1. 品質レビュー（Issue目的との整合性確認）
2. **仕様ファイルのステータス更新**（completed）
3. **`in-progress` ラベルを削除**
4. Commit & Push
5. PR作成 & マージ
6. **Issueクローズ**
7. Worktree削除
8. コンテキスト整理（/compact）

## Usage

```
/issue/finish
```

## vs /commit/push（途中保存）

タスクが**まだ完了していない**場合は `/commit/push` を使用してください。

| スキル | 用途 | Issueクローズ | Worktree削除 |
|-------|------|--------------|--------------|
| `/issue/finish` | タスク完了 | ✅ する | ✅ する |
| `/commit/push` | 途中保存 | ❌ しない | ❌ しない |

## Implementation

### Step 0: 未回答のQA質問を確認

`/qa/ask` で投稿した質問に未回答がないか確認します。

```python
from pathlib import Path
import json

questions_file = Path("docs/qa/questions.jsonl")
answers_file = Path("docs/qa/answers.jsonl")

# 質問がなければスキップ
if not questions_file.exists():
    # QAなし、続行
    pass
else:
    # 質問IDを収集
    question_ids = set()
    for line in questions_file.read_text().strip().split('\n'):
        if line:
            q = json.loads(line)
            question_ids.add(q['id'])

    # 回答済みIDを収集
    answered_ids = set()
    if answers_file.exists():
        for line in answers_file.read_text().strip().split('\n'):
            if line:
                a = json.loads(line)
                answered_ids.add(a['id'])

    # 未回答の質問
    unanswered = question_ids - answered_ids
    if unanswered:
        # 未回答の質問ごとにIssueを作成
        for qid in unanswered:
            create_qa_followup_issue(qid)
```

未回答の質問がある場合、各質問に対してフォローアップIssueを作成します。

```python
def create_qa_followup_issue(question_id: str) -> None:
    """未回答の質問に対するフォローアップIssueを作成"""
    store = QAStore(Path("docs/qa"))
    question = store.get_question_by_id(question_id)

    if not question:
        return

    title = f"[QA] {question_id}: {question.question[:50]}"
    body = f"""## 概要

Issue #{question.issue} で仮決定した内容について、確認が必要です。

## 質問内容

{question.question}

## 仮決定

{question.decision or "なし"}

## 対応

- [ ] 回答を確認
- [ ] 必要に応じて実装を修正

## 関係

- Parent: #{question.issue}
"""

    # gh コマンドでIssue作成
    # gh issue create --title "..." --body "..." --label "qa-pending"
```

作成されるIssue:
- タイトル: `[QA] Q001: 質問内容...`
- ラベル: `qa-pending`
- 親Issueへのリンク付き

### Step 1: 仕様ファイルのステータス更新

```bash
# Issue番号の取得
BRANCH=$(git branch --show-current)
ISSUE_ID=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# 仕様ファイルを特定
SPEC_FILE=$(ls .spec/issues/${ISSUE_ID}-*.md 2>/dev/null | head -1)
```

仕様ファイルが存在する場合、メタ情報を更新：
- `ステータス: draft` → `ステータス: completed`
- `完了日: YYYY-MM-DD` を追加
- 変更履歴に完了記録を追加

### Step 1.5: in-progress ラベルを削除

```bash
gh issue edit "$ISSUE_ID" --remove-label "in-progress"
```

### Step 2: /commit/merge 実行

Skillツールを使って `/commit/merge` コマンドを実行：

```xml
<invoke name="Skill">
<parameter name="skill">commit/merge</parameter>
</invoke>
```

すべての実装詳細は `/commit/merge` コマンドに委譲されます。

## Note

- `/issue/finish` は仕様ファイルのステータス更新 + `/commit/merge` を実行
- どちらもタスク完了時に使用（Issueをクローズする）
- 途中保存したい場合は `/commit/push` を使用
