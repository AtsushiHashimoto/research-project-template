---
description: Process backlog - unblock then issue-ify ready items (バックログ処理)
---

# Issue Backlog

バックログ (`docs/backlog.md`) を処理します:
1. `/issue/unblock` でブロッカー解消Issueを作成
2. ブロッカーがない項目をIssue化
3. Issue化した項目を backlog.md から削除

## Usage

```
/issue/backlog              # フル処理（unblock + Issue化 + 削除）
/issue/backlog --dry-run    # 分析のみ、変更しない
/issue/backlog --skip-unblock  # unblockをスキップ（Issue化のみ）
```

## Concept

```
┌─────────────────────────────────────────────────────────────┐
│                    /issue/backlog                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Step 1: /issue/unblock 呼び出し                          │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ ブロッカー分析 → 自動解消Issue作成                  │  │
│   │ 例: Issue #70: test(retriever): Add real FAISS E2E │  │
│   └─────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│   Step 2: ブロッカーなし項目のIssue化                      │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ BL-007: ROS2 Executor                               │  │
│   │   ブロッカー: HTTPExecutor実装完了 ✅               │  │
│   │   → Issue #71: feat(executor): Add ROS2 Executor   │  │
│   └─────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│   Step 3: backlog.md から削除                              │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ docs/backlog.md:                                    │  │
│   │ - BL-007 セクションを削除                           │  │
│   │ - "Moved to Issue #71" コメントを残す（オプション） │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Workflow

### Phase 1: /issue/unblock 呼び出し

```
Skill(skill="issue/unblock")
```

これにより:
- ブロッカーが分類される（🤖自動 / 👤ユーザー / ⏸️依存待ち）
- 自動解消可能なブロッカーのIssueが作成される

### Phase 2: ブロッカーなし項目の特定

```
Task(subagent_type="general-purpose", prompt="
docs/backlog.md を分析し、ブロッカーがない（着手可能な）項目を特定してください。

## 着手可能の条件

1. 「後回しにした理由」が解消されている
   - 前提条件となる実装が完了している
   - 依存するBL項目がない、または依存BLが完了済み

2. ユーザー確認が不要
   - 実ハードウェア/サーバーでの確認が不要
   - 実運用検証が不要

## 確認方法

各項目について:
1. 「後回しにした理由」を確認
2. その理由が解消されているかをコードベースで確認
3. 依存BL項目があれば、その状態を確認

## 出力形式

### 着手可能な項目

| BL ID | タイトル | 理由が解消された根拠 |
|-------|---------|---------------------|
| BL-007 | ROS2 Executor | HTTPExecutor実装完了 |

### 着手不可の項目

| BL ID | タイトル | 残ブロッカー |
|-------|---------|-------------|
| BL-001 | FeedbackMonitor | 実ハードウェア確認必要（👤） |
")
```

### Phase 3: Issue作成

着手可能な項目をIssue化:

```bash
for BL_ITEM in $READY_ITEMS; do
  BL_ID=$(echo "$BL_ITEM" | jq -r '.id')
  BL_TITLE=$(echo "$BL_ITEM" | jq -r '.title')
  BL_DESCRIPTION=$(echo "$BL_ITEM" | jq -r '.description')
  BL_CONSIDERATIONS=$(echo "$BL_ITEM" | jq -r '.considerations')

  NEW_ISSUE=$(gh issue create \
    --title "feat: ${BL_TITLE}" \
    --body "## 概要

${BL_DESCRIPTION}

## 背景

バックログ項目 ${BL_ID} より。
ブロッカーが解消されたため、Issue化しました。

## 実装時の考慮点

${BL_CONSIDERATIONS}

## 関係
- From Backlog: ${BL_ID}

---
*このIssueは /issue/backlog により自動生成されました*" \
    --label "feature")

  echo "Created: $NEW_ISSUE for $BL_ID"
  CREATED_ISSUES+=("$BL_ID:$NEW_ISSUE")
done
```

### Phase 4: backlog.md から削除

Issue化した項目を backlog.md から削除:

```bash
for ITEM in $CREATED_ISSUES; do
  BL_ID=$(echo "$ITEM" | cut -d: -f1)
  ISSUE_URL=$(echo "$ITEM" | cut -d: -f2)

  # 該当セクションを削除（または移動コメントを残す）
  # セクションの開始: ### BL-XXX:
  # セクションの終了: 次の ### または ---

  # オプション1: 完全削除
  sed -i "/### ${BL_ID}:/,/^---$/d" docs/backlog.md

  # オプション2: 移動コメントを残す（推奨）
  # sed -i "s/### ${BL_ID}:.*/### ${BL_ID}: [Moved to ${ISSUE_URL}]/" docs/backlog.md
done

# 変更をコミット
git add docs/backlog.md
git commit -m "chore(backlog): Move ${BL_ID} to Issue

Items moved to GitHub Issues:
$(for ITEM in $CREATED_ISSUES; do echo "- $ITEM"; done)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Phase 5: 完了報告

```markdown
# /issue/backlog 完了

**実行日時**: YYYY-MM-DD HH:MM

---

## 処理結果

### ブロッカー解消Issue（/issue/unblock）

| Issue | タイトル | Unblocks |
|-------|---------|----------|
| #70 | test(retriever): Add real FAISS E2E | BL-003, BL-005 |

### 着手可能 → Issue化

| BL ID | タイトル | 作成Issue |
|-------|---------|----------|
| BL-007 | ROS2 Executor | #71 |

### backlog.md 更新

- BL-007 を削除（Issue #71 へ移動）

---

## 残りのバックログ

| BL ID | タイトル | 状態 |
|-------|---------|------|
| BL-001 | FeedbackMonitor | 👤 ユーザー確認待ち |
| BL-002 | Notifier | ⏸️ BL-001依存 |
| BL-003 | SONAR移行 | 🤖 Issue #70 で解消予定 |

## 次のステップ

1. `/issue/auto 70 71` で作成されたIssueを処理
2. ユーザー確認項目は手動でテスト実施
```

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 分析のみ、Issue作成・backlog更新しない |
| `--skip-unblock` | /issue/unblock をスキップ |
| `--keep-in-backlog` | Issue作成するがbacklog.mdから削除しない |
| `--comment-only` | 削除せず「Moved to #XX」コメントを残す |

## Safety Features

1. **dry-run モード**: 変更前に計画を確認可能
2. **段階的処理**: unblock → Issue化 → 削除 の順序
3. **コミット記録**: backlog.md の変更履歴が残る
4. **移動コメント**: 削除時にIssue番号を記録（オプション）

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/unblock` | Phase 1 で呼び出し |
| `/issue/cycle` | 収束後に /issue/backlog を呼び出し |
| `/issue/auto` | 作成されたIssueを自動処理 |
