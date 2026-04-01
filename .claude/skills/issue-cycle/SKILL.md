---
description: Run auto→gaps→auto loop until convergence (継続的自動処理ループ)
argument-hint: [issue_ids...] [max_cycles]
---

# Issue Cycle

`/issue/auto` → `/issue/gaps` → `/review-integrity` → `/issue/auto` のループを収束まで実行します。

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
┌──────────────────────────────────────────────────────────────────┐
│                    /issue/cycle                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Cycle 1:                                                       │
│   ┌──────────────┐   ┌──────────────┐   ┌───────────────────┐  │
│   │ /issue/auto  │ → │ /issue/gaps  │ → │/review-integrity  │  │
│   │ #5, #7       │   │ → #10, #11   │   │ → #12 (bug found) │  │
│   └──────────────┘   └──────────────┘   └───────────────────┘  │
│                                                │                 │
│                                                v                 │
│   Cycle 2:                                                       │
│   ┌──────────────┐   ┌──────────────┐   ┌───────────────────┐  │
│   │ /issue/auto  │ → │ /issue/gaps  │ → │/review-integrity  │  │
│   │ #10-#12      │   │ → (なし)     │   │ → (クリーン)      │  │
│   └──────────────┘   └──────────────┘   └───────────────────┘  │
│                                                │                 │
│                                                v                 │
│   ┌─────────────────────────────────┐                           │
│   │ Backlog Check                   │                           │
│   └─────────────────────────────────┘                           │
│                    │                                             │
│                    v                                             │
│   Convergence! (gaps=0 AND integrity=clean)                     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
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
   │   3. /review-integrity でバグパターン・品質チェック          │
   │   4. 新規Issueがあれば次サイクルへ                          │
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

→ 新規Issue が作成された場合、gaps_issues に追加

#### Step 2.5: /review-integrity

```
Skill(skill="review-integrity")
```

→ バグパターン・デッドコード・配線不備を検出
→ **全ての深刻度（Critical / High / Medium / Low）の問題に対して Issue を作成**し integrity_issues に追加

**★★★ 重要: 全深刻度をIssue化する ★★★**

`/review-integrity` で検出された問題は、深刻度に関わらず **全て** Issue を作成して次サイクルで修正する。
「Low だから放置」「Medium だから後回し」は禁止。コードベースの品質を徹底的に維持する。

```python
# review-integrity の結果を処理
for finding in integrity_findings:
    # Critical/High/Medium/Low 全てIssue化
    issue_id = gh_issue_create(
        title=f"{finding.severity_label}: {finding.title}",
        body=f"""## 概要
{finding.description}

## 該当箇所
- {finding.file}:{finding.line}

## 修正案
{finding.fix_suggestion}

## 深刻度
{finding.severity}

## 発見経緯
/review-integrity で検出。

---
*このIssueは /issue/cycle の review-integrity により自動生成されました*""",
        labels=[finding.label, "integrity"]
    )
    integrity_issues.append(issue_id)
```

深刻度に応じたIssue化ルール:

| 深刻度 | ラベル | Issue化 | 例 |
|--------|--------|---------|-----|
| Critical | bug | **個別Issue** | 型不一致、未実装Protocol |
| High | bug | **個別Issue** | 配線不備、セキュリティ |
| Medium | chore | **まとめて1 Issue** | テスト不足、DRY違反 |
| Low | chore | **まとめて1 Issue** | TODO棚卸し、命名統一 |

**まとめルール**: Medium 以下の問題は 1つの Issue にまとめて効率的に処理する。
タイトル例: `chore: integrity review — Medium/Low N件修正`
本文に全件のチェックリストを含め、一括で修正する。

```python
# Critical/High は個別Issue
for finding in [f for f in findings if f.severity in ("critical", "high")]:
    issue_id = create_individual_issue(finding)
    integrity_issues.append(issue_id)

# Medium/Low はまとめて1 Issue
minor_findings = [f for f in findings if f.severity in ("medium", "low")]
if minor_findings:
    issue_id = create_batch_issue(minor_findings)
    integrity_issues.append(issue_id)
```

#### Step 3: 判定

```python
newly_created_issues = gaps_issues + integrity_issues
if newly_created_issues:
    if cycle_count < max_cycles:
        CURRENT_ISSUE_IDS = newly_created_issues
        continue  # 次サイクルへ
    else:
        print("最大サイクル到達。残りIssue:", newly_created_issues)
        break
else:
    print("収束しました（gaps=0 AND integrity=全深刻度クリーン）")
    break
```

**収束条件**: gaps で新規 Issue = 0 **かつ** integrity で全深刻度の問題 = 0

#### Step 4: サイクルスナップショット

```bash
# 各サイクル完了時にスナップショット
CYCLE_SNAPSHOT="cycle-${CYCLE_NUM}/$(date +%Y%m%d-%H%M%S)"
git branch "$CYCLE_SNAPSHOT" HEAD
```

### Phase Backlog: バックログ処理（収束後）

Issue/gaps のサイクルが収束した後、`/issue/backlog` を呼び出してバックログを処理します。

```
Skill(skill="issue-backlog")
```

`/issue/backlog` は以下を実行します:
1. `/issue/unblock` でブロッカー解消Issueを作成（自動解消可能なもののみ）
2. ブロッカーがない項目をIssue化
3. Issue化した項目を `docs/backlog.md` から削除

#### 継続判定

`/issue/backlog` で新規Issueが作成された場合、メインループに戻ります:

```python
if backlog_created_issues:
    if cycle_count < max_cycles:
        CURRENT_ISSUE_IDS = backlog_created_issues
        continue  # メインループへ戻る
    else:
        print("最大サイクル到達。残りIssue:", backlog_created_issues)
        break
else:
    print("完全収束しました")
    break
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

## バックログ処理結果（/issue/backlog）

| 処理 | 結果 |
|------|------|
| ブロッカー解消Issue | #15, #16 |
| 着手可能→Issue化 | BL-007 → #17 |
| backlog.md更新 | BL-007 削除 |
| 👤 ユーザー確認待ち | BL-001, BL-006（/qa/ask で通知済み） |

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
| `--skip-backlog` | バックログ処理をスキップ |

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
| `/issue-auto` | 各サイクルで呼び出し |
| `/issue-gaps` | 各サイクルで呼び出し（Issue-実装間の乖離検出） |
| `/review-integrity` | 各サイクルで呼び出し（バグパターン・品質チェック） |
| `/issue-backlog` | 収束後に呼び出し |
| `/issue-unblock` | backlog 内部で使用 |
| `/issue-scan` | gaps 内部で使用 |
| `/issue-diff` | gaps 内部で使用 |
| `/qa-ask` | unblock でユーザー確認必要項目を通知 |
