---
description: Analyze backlog blockers and create issues to resolve them (ブロッカー解消Issue作成)
---

# Issue Unblock

バックログ (`docs/backlog.md`) のブロッカーを分析し、自動解消可能なものについてIssueを作成します。

**注意**: このスキルはブロッカー解消のみを担当します。ブロッカーがない項目のIssue化は `/issue/backlog` が担当します。

## Usage

```
/issue/unblock              # バックログ分析・Issue作成
/issue/unblock --dry-run    # 分析のみ、Issue作成しない
/issue/unblock --all        # ユーザー確認必要な項目も含めて報告
```

## Concept

```
┌─────────────────────────────────────────────────────────────┐
│                    /issue/unblock                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   docs/backlog.md                                           │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ BL-001: FeedbackMonitor     → 👤 ユーザー確認必要   │  │
│   │ BL-002: Notifier            → ⏸️ BL-001依存        │  │
│   │ BL-003: SONAR移行           → 🤖 自動解消可能      │  │
│   │ BL-007: ROS2 Executor       → 👤 ユーザー確認必要   │  │
│   │ BL-008: duo publish         → 🤖 自動解消可能      │  │
│   └─────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ 🤖 自動解消可能なブロッカー                         │  │
│   │                                                     │  │
│   │ BL-003 ブロッカー: 実RAGテスト不足                  │  │
│   │   → Issue: test(retriever): Add real FAISS E2E     │  │
│   │                                                     │  │
│   │ BL-008 ブロッカー: duo-ctl add 未実装               │  │
│   │   → Issue: feat(cli): Implement duo-ctl add        │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Workflow

### Phase 1: バックログ読み込み

```bash
BACKLOG_FILE="docs/backlog.md"
if [ ! -f "$BACKLOG_FILE" ]; then
  echo "バックログファイルが存在しません"
  exit 0
fi
```

バックログをパースし、各項目を抽出:
- ID (BL-XXX)
- タイトル
- 概要
- 後回しにした理由
- 実装時の考慮点

### Phase 2: ブロッカー分類

各バックログ項目の「後回しにした理由」を分析し、分類します。

```
Task(subagent_type="general-purpose", prompt="
docs/backlog.md の各項目について、ブロッカーを分類してください。

## 分類ルール

### 🤖 自動解消可能
以下のパターンに該当する場合:
- 「実装」「コード追加」が必要 → コード実装で解消
- 「テスト追加」が必要 → テスト実装で解消
- 「Mockを実際の〜に置き換え」 → コード変更で解消
- 「設計が完了してから」 → 設計ドキュメントがあれば解消

### 👤 ユーザー確認必要
以下のパターンに該当する場合:
- 「実ハードウェア」「実サーバー」での確認が必要
- 「実運用」「本番環境」での検証が必要
- 「外部サービス」との連携確認が必要
- ユーザーの判断・承認が必要

### ⏸️ 依存待ち
- 他のBL項目が前提条件として明記されている場合
- 例: 「BL-001が先に必要」

## 出力形式

| BL ID | タイトル | 分類 | ブロッカー | 解消方法 |
|-------|---------|------|-----------|----------|
| BL-001 | ... | 👤/🤖/⏸️ | ... | ... |
")
```

### Phase 3: Gap分析（自動解消可能な項目）

🤖 自動解消可能と判定された項目について、具体的な不足を分析:

```
Task(subagent_type="general-purpose", prompt="
以下のバックログ項目について、ブロッカー解消に必要な実装を特定してください。

## 対象項目
${AUTO_RESOLVABLE_ITEMS}

## 分析内容
1. 現在の実装状況を確認
2. 不足している機能/テストを特定
3. Issue作成用の情報を出力

## 出力形式（各項目）
- **BL ID**: BL-XXX
- **ブロッカー**: 〜が不足
- **Issue タイトル**: feat/test/fix(scope): description
- **Issue 本文**: 概要、タスク、関係
- **推奨ラベル**: feature/bug/chore
")
```

### Phase 4: Issue作成

自動解消可能なブロッカーに対してIssueを作成:

```bash
for BLOCKER in $AUTO_RESOLVABLE_BLOCKERS; do
  BL_ID=$(echo "$BLOCKER" | jq -r '.bl_id')
  ISSUE_TITLE=$(echo "$BLOCKER" | jq -r '.issue_title')
  ISSUE_BODY=$(echo "$BLOCKER" | jq -r '.issue_body')
  LABEL=$(echo "$BLOCKER" | jq -r '.label')

  gh issue create \
    --title "$ISSUE_TITLE" \
    --body "## 概要

${ISSUE_BODY}

## 関係
- Unblocks: ${BL_ID} in docs/backlog.md

---
*このIssueは /issue/unblock により自動生成されました*" \
    --label "$LABEL"
done
```

### Phase 5: ユーザー確認必要項目の通知

👤 ユーザー確認必要と判定された項目がある場合、`/qa/ask` で通知します:

```bash
if [ -n "$USER_ACTION_REQUIRED_ITEMS" ]; then
  # QA質問を投稿
  /qa/ask --type deferred "バックログのユーザー確認待ち項目があります。

以下の項目は実ハードウェア/実運用での確認が必要です:

$(for ITEM in $USER_ACTION_REQUIRED_ITEMS; do
  BL_ID=$(echo "$ITEM" | jq -r '.id')
  BL_TITLE=$(echo "$ITEM" | jq -r '.title')
  REQUIRED_ACTION=$(echo "$ITEM" | jq -r '.required_action')
  echo "- **${BL_ID}**: ${BL_TITLE}"
  echo "  必要なアクション: ${REQUIRED_ACTION}"
done)

確認完了後、該当項目のIssueを手動で作成してください。"
fi
```

これにより、ユーザーが不在でも Slack/Discord で通知を受け取れます。

### Phase 6: 完了報告

```markdown
# /issue/unblock 完了

**実行日時**: YYYY-MM-DD HH:MM

---

## バックログ分析結果

| BL ID | タイトル | 分類 | 状態 |
|-------|---------|------|------|
| BL-001 | FeedbackMonitor | 👤 ユーザー | 実ハードウェア確認待ち |
| BL-002 | Notifier | ⏸️ 依存待ち | BL-001完了後 |
| BL-003 | SONAR移行 | 🤖 自動 | Issue #XX 作成 |
| BL-008 | duo publish | 🤖 自動 | Issue #XX 作成 |

## 作成したIssue

| Issue | タイトル | Unblocks |
|-------|---------|----------|
| #XX | test(retriever): Add real FAISS E2E tests | BL-003, BL-005 |
| #XX | feat(cli): Implement duo-ctl add | BL-008 |

## ユーザーアクション必要

以下の項目はユーザーによる確認/テストが必要です:

| BL ID | タイトル | 必要なアクション |
|-------|---------|-----------------|
| BL-001 | FeedbackMonitor | 実APIサーバーとの統合テスト実施 |
| BL-007 | ROS2 Executor | HTTPExecutorの実運用検証 |

---

## 次のステップ

1. 作成されたIssueを `/issue/auto` で処理
2. ユーザーアクション項目を手動で確認
3. 確認完了後、該当BL項目のIssueを手動作成
```

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 分析のみ、Issue作成しない |
| `--all` | ユーザー確認必要な項目も詳細報告 |
| `--create-all` | ユーザー確認必要な項目もIssue作成（確認Issueとして） |

## ブロッカー分類パターン

### 🤖 自動解消可能

| パターン | 解消方法 |
|---------|----------|
| 「〜の実装が必要」 | コード実装 |
| 「テストが不足」「Mockを置き換え」 | テスト追加 |
| 「設計完了後」+ 設計ドキュメント存在 | 実装開始可能 |
| 「〜が固まった後」+ 実装完了 | 実装開始可能 |

### 👤 ユーザー確認必要

| パターン | 理由 |
|---------|------|
| 「実ハードウェア」「実サーバー」 | 物理環境が必要 |
| 「実運用」「本番環境」 | 本番相当環境が必要 |
| 「外部サービス連携」 | 外部依存 |
| 「ユーザー判断」「ビジネス判断」 | 人間の決定が必要 |

## Safety Features

1. **dry-run モード**: Issue作成前に計画を確認可能
2. **ユーザー確認項目の分離**: 自動処理と手動処理を明確に分離
3. **依存関係考慮**: 依存BLが未完了の項目はスキップ
4. **Unblocks 関係記録**: 作成IssueにどのBL項目を解消するか記録

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/backlog` | /issue/unblock を呼び出した後、ブロッカーなし項目をIssue化 |
| `/issue/cycle` | 収束後に /issue/backlog を呼び出し（間接的に unblock も実行） |
| `/issue/gaps` | Gap分析ロジックを共有 |
| `/issue/auto` | 作成されたIssueを自動処理 |
