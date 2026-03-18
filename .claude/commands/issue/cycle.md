---
description: Run auto→gaps→auto loop until convergence (継続的自動処理ループ)
argument-hint: [issue_ids...] [max_cycles]
---

# Issue Cycle

`/issue/auto` → `/issue/gaps` → `/issue/auto` のループを収束まで実行します。

## Usage

```
/issue/cycle              # デフォルト（収束まで、最大10サイクル）
/issue/cycle 3回まで      # 最大3サイクル
/issue/cycle 1回だけ      # 1サイクルのみ
/issue/cycle 完了するまで # 収束まで（明示的）
/issue/cycle #5 #7 2回    # 指定Issue、最大2サイクル
/issue/cycle 5 7 --max 3  # 指定Issue、最大3サイクル
```

## Concept

```
┌─────────────────────────────────────────────────────────────┐
│                    /issue/cycle                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Cycle 1:                                                  │
│   ┌───────────────┐    ┌───────────────┐                   │
│   │ /issue/auto   │ -> │ /issue/gaps   │                   │
│   │ #5, #7        │    │ -> #10, #11   │  (新規Issue作成)   │
│   └───────────────┘    └───────────────┘                   │
│                              │                              │
│                              v                              │
│   Cycle 2:                                                  │
│   ┌───────────────┐    ┌───────────────┐                   │
│   │ /issue/auto   │ -> │ /issue/gaps   │                   │
│   │ #10, #11      │    │ -> (なし)     │  (新規Issueなし)   │
│   └───────────────┘    └───────────────┘                   │
│                              │                              │
│                              v                              │
│   ┌───────────────────────────────────┐                    │
│   │ Backlog Check                     │                    │
│   │ docs/backlog.md をスキャン        │                    │
│   │ -> 着手可能: BL-006              │  (Issue作成提案)    │
│   └───────────────────────────────────┘                    │
│                              │                              │
│                              v                              │
│   Convergence! (収束)                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Workflow

### Phase 0: 引数パース

1. **数値パターン検出**
   ```
   /(\d+)\s*(回|サイクル|cycle|cycles)/i
   ```
   例: "3回まで" → max_cycles=3

2. **キーワード検出**
   - "1回だけ", "once" → max_cycles=1
   - "完了まで", "完了するまで", "until done" → max_cycles=10 (実質無限)

3. **Issue ID検出**
   ```
   /#?(\d+)/g
   ```
   例: "#5 #7" → initial_ids=[5, 7]

4. **--max オプション**
   ```
   --max\s+(\d+)
   ```
   例: "--max 3" → max_cycles=3

5. **デフォルト値**
   - max_cycles=10
   - initial_ids=[] (空の場合は全open Issueが対象)

### Phase 1: 初期化

1. **スナップショット作成**
   ```bash
   SNAPSHOT_BRANCH="pre-cycle/$(date +%Y%m%d-%H%M%S)"
   git branch "$SNAPSHOT_BRANCH" main
   ```

2. **ユーザー確認**
   ```
   ┌─────────────────────────────────────────────────────────────┐
   │ /issue/cycle 実行確認                                       │
   ├─────────────────────────────────────────────────────────────┤
   │ 初期Issue: #5, #7                                           │
   │ 最大サイクル: 3                                             │
   │ スナップショット: pre-cycle/20260318-120000                 │
   │                                                             │
   │ 各サイクルで:                                               │
   │   1. /issue/auto で処理                                     │
   │   2. /issue/gaps で乖離検出・Issue作成                      │
   │   3. 新規Issueがあれば次サイクルへ                          │
   │                                                             │
   │ 実行しますか？                                              │
   └─────────────────────────────────────────────────────────────┘
   ```

### Phase 2-N: サイクル実行

各サイクルで以下を実行:

#### Step 1: /issue/auto

```
Skill(skill="issue/auto", args="${CURRENT_ISSUE_IDS}")
```

#### Step 2: /issue/gaps

```
Skill(skill="issue/gaps")
```

#### Step 3: 判定

```python
if newly_created_issues:
    if cycle_count < max_cycles:
        CURRENT_ISSUE_IDS = newly_created_issues
        continue  # 次サイクルへ
    else:
        print("最大サイクル到達。残りIssue:", newly_created_issues)
        break
else:
    print("収束しました")
    break
```

#### Step 4: サイクルスナップショット

```bash
# 各サイクル完了時にスナップショット
CYCLE_SNAPSHOT="cycle-${CYCLE_NUM}/$(date +%Y%m%d-%H%M%S)"
git branch "$CYCLE_SNAPSHOT" HEAD
```

### Phase Backlog: バックログチェック（収束後）

Issue/gaps のサイクルが収束した後、`docs/backlog.md` をチェックして着手可能な項目がないか確認します。

#### Step 1: バックログ読み込み

```bash
# docs/backlog.md を読み込み
BACKLOG_FILE="docs/backlog.md"
if [ -f "$BACKLOG_FILE" ]; then
  BACKLOG_CONTENT=$(cat "$BACKLOG_FILE")
else
  echo "バックログファイルが存在しません"
  BACKLOG_CONTENT=""
fi
```

#### Step 2: 各項目の着手可否判定

```
Task(subagent_type="general-purpose", prompt="
docs/backlog.md の各バックログ項目について、着手可能かどうかを判定してください。

## 判定基準

各項目の「後回しにした理由」を確認し、その理由が解消されているかをコードベースと照合します。

例:
- BL-001 (FeedbackMonitor): 「パイプライン全体を動かすことを優先」
  → Phase 1/2 E2Eテストが完了していれば着手可能
- BL-006 (duo-planner統合): 「duo-core単体で動作確認が取れてから」
  → Phase 2 E2Eテストが完了していれば着手可能
- BL-007 (ROS2 Executor): 「HTTPExecutorの実装が固まった後」
  → HTTPExecutorが実装済みなら着手可能

## 出力形式

| BL ID | タイトル | 着手可否 | 理由 |
|-------|---------|---------|------|
| BL-001 | FeedbackMonitor | ✅ 可能 | Phase 2 E2E完了済み |
| BL-002 | Notifier | ❌ 不可 | BL-001が先に必要 |
| ...

## 着手可能な項目がある場合

Issue作成を提案:
- タイトル案
- 推奨ラベル
- 依存関係
")
```

#### Step 3: Issue作成提案

着手可能な項目がある場合、ユーザーに確認を求めます:

```
┌─────────────────────────────────────────────────────────────┐
│ バックログから着手可能な項目が見つかりました                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ✅ BL-006: duo-planner との統合                            │
│    理由: Phase 2 E2Eテストが完了し、duo-core単体動作確認済み│
│                                                             │
│ ✅ BL-007: ROS2 Executor                                   │
│    理由: HTTPExecutor が実装済み                            │
│                                                             │
│ Issueを作成しますか？                                       │
│ [はい、全て作成]                                            │
│ [選択して作成]                                              │
│ [いいえ、スキップ]                                          │
└─────────────────────────────────────────────────────────────┘
```

#### Step 4: Issue作成（承認時）

```bash
for BL_ITEM in $READY_BACKLOG_ITEMS; do
  BL_ID=$(echo "$BL_ITEM" | jq -r '.id')
  BL_TITLE=$(echo "$BL_ITEM" | jq -r '.title')
  BL_DESCRIPTION=$(echo "$BL_ITEM" | jq -r '.description')
  BL_CONSIDERATIONS=$(echo "$BL_ITEM" | jq -r '.considerations')

  gh issue create \
    --title "feat: ${BL_TITLE}" \
    --body "## 概要

${BL_DESCRIPTION}

## 背景

バックログ項目 ${BL_ID} より。
\`/issue/cycle\` のバックログチェックで着手可能と判定されました。

## 実装時の考慮点

${BL_CONSIDERATIONS}

## 関係
- Backlog: ${BL_ID}

---
*このIssueは /issue/cycle のバックログチェックにより自動生成されました*" \
    --label "feature"

  # バックログファイルに着手開始を記録
  echo "<!-- Started: $(date +%Y-%m-%d) as Issue #XX -->" >> docs/backlog.md
done
```

### Phase Final: 完了報告

```markdown
# /issue/cycle 完了

**実行日時**: YYYY-MM-DD HH:MM
**サイクル数**: 3
**収束**: Yes / No (最大到達)

---

## サイクル履歴

### Cycle 1

| 処理Issue | 結果 |
|----------|------|
| #5 | ✅ 完了 |
| #7 | ✅ 完了 |

**新規Issue**: #10, #11

### Cycle 2

| 処理Issue | 結果 |
|----------|------|
| #10 | ✅ 完了 |
| #11 | ✅ 完了 |

**新規Issue**: なし

---

## スナップショット

| ポイント | ブランチ |
|---------|---------|
| 開始前 | pre-cycle/20260318-120000 |
| Cycle 1後 | cycle-1/20260318-121500 |
| Cycle 2後 | cycle-2/20260318-123000 |

## バックログチェック結果

| BL ID | タイトル | 状態 | アクション |
|-------|---------|------|-----------|
| BL-006 | duo-planner統合 | ✅ 着手可能 | Issue #15 作成 |
| BL-007 | ROS2 Executor | ✅ 着手可能 | Issue #16 作成 |
| BL-001 | FeedbackMonitor | ❌ 未着手 | 依存: BL-002 |

## ロールバック

特定サイクルに戻す場合:
```bash
git checkout cycle-1/20260318-121500
git reset --hard cycle-1/20260318-121500
```

完全に元に戻す場合:
```bash
git checkout pre-cycle/20260318-120000
git reset --hard pre-cycle/20260318-120000
```
```

### Phase Cleanup: コンテキスト整理

全サイクル完了後、コンテキストを整理：

```
/compact
```

## Safety Features

### 1. ハード上限

最大10サイクル（無限ループ防止）:

```python
HARD_LIMIT = 10
if cycle_count >= HARD_LIMIT:
    print("安全上限に達しました")
    break
```

### 2. 自信度チェック

各サイクルの `/issue/auto` で自信度 < 50% の場合は停止:

```python
if auto_confidence < 50:
    print("自信度が低いため停止")
    print("手動で確認してください")
    break
```

### 3. サイクルスナップショット

各サイクル完了時にスナップショットを作成:

```bash
git branch "cycle-${N}/$(date +%Y%m%d-%H%M%S)" HEAD
```

### 4. 中断時のリカバリー

中断した場合、最後のスナップショットから再開可能:

```bash
# 状態確認
git branch | grep "cycle-"

# 最後のサイクルから再開
/issue/cycle --resume cycle-2
```

## Options

| オプション | 説明 |
|-----------|------|
| `--max N` | 最大サイクル数を指定 |
| `--dry-run` | 実際の変更は行わず、計画のみ表示 |
| `--no-confirm` | 確認プロンプトをスキップ |
| `--resume BRANCH` | 指定ブランチから再開 |
| `--skip-backlog` | バックログチェックをスキップ |
| `--backlog-only` | バックログチェックのみ実行（サイクルなし） |

## Natural Language Parsing

引数は自然言語で指定可能:

| 入力 | 解釈 |
|------|------|
| `3回まで` | max_cycles=3 |
| `1回だけ` | max_cycles=1 |
| `once` | max_cycles=1 |
| `完了するまで` | max_cycles=10 |
| `until done` | max_cycles=10 |
| `#5 #7 2回` | initial_ids=[5,7], max_cycles=2 |
| `5 7 --max 3` | initial_ids=[5,7], max_cycles=3 |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/auto` | 各サイクルで呼び出し |
| `/issue/gaps` | 各サイクルで呼び出し |
| `/issue/scan` | gaps 内部で使用 |
| `/issue/diff` | gaps 内部で使用 |
