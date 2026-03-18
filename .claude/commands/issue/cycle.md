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
