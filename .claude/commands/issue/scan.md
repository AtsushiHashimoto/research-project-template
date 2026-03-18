---
description: Scan all issues and analyze their status (全Issue状態のスキャン)
---

# Issue Scanner

全Issueの状態をスキャンし、分類レポートを生成します。

## Usage

```
/issue/scan              # 全open Issueをスキャン
/issue/scan --all        # closed も含めてスキャン
/issue/scan --recent 7   # 直近7日間に更新されたIssueのみ
```

## Output

スキャン結果は以下のカテゴリに分類されます:

- **Open Issues**: 進行中のIssue（Active/Blocked/Out-of-date）
- **Potentially Outdated**: 古くなっている可能性のあるIssue
- **Implementation Without Issue**: Issueなしで実装されたコード

## Workflow

### Phase 1: Issue収集

1. **GitHub Issueの取得**
   ```bash
   # Open Issues
   gh issue list --state open --json number,title,body,labels,createdAt,updatedAt,assignees

   # Recent Closed Issues (オプション)
   gh issue list --state closed --json number,title,body,labels,closedAt --limit 50
   ```

2. **関連PRの取得**
   ```bash
   gh pr list --state all --json number,headRefName,state,mergedAt
   ```

### Phase 2: ブランチ対応確認

1. **各Issueに対応するブランチを確認**
   ```bash
   git branch -a --list "*/${ISSUE_ID}-*"
   ```

2. **ステータス判定**
   - ブランチあり → `in_progress`
   - ブランチなし、`blocked` ラベルなし → `pending`
   - `blocked` ラベルあり → `blocked`
   - `out-of-date` ラベルあり → `out-of-date`

### Phase 3: 乖離検出

1. **長期未更新の検出**
   - 最終更新から30日以上経過
   - `abandoned` 候補としてフラグ

2. **関連Issue検出**
   - Issue本文内の `#N` 参照を解析
   - `depends on`, `blocked by`, `superseded by` を検出

3. **重複候補検出**
   - タイトルの単語重複率を計算
   - 80%以上で重複候補としてフラグ

### Phase 4: 未追跡コード検出

1. **最近追加されたファイル**
   ```bash
   git log --since="30 days ago" --diff-filter=A --name-only --format=""
   ```

2. **対応Issue確認**
   - コミットメッセージに `#N` がない
   - コード内に `Refs #N` がない
   → 未追跡としてフラグ

### Phase 5: レポート生成

**issue-scanner エージェントを使用**:

```
Task(subagent_type="general-purpose", prompt="
agents/issue-scanner.md の定義に従って、Issueスキャンレポートを生成してください。

## 収集データ
${COLLECTED_DATA}

## 出力
agents/issue-scanner.md の出力形式に従ってレポートを生成。
結果は Markdown 形式で出力してください。
")
```

## Options

| オプション | 説明 |
|-----------|------|
| `--all` | closed Issue も含めてスキャン |
| `--recent N` | 直近N日間に更新されたIssueのみ |
| `--output FILE` | 結果をファイルに出力 |
| `--json` | JSON形式で出力 |

## Agent References

| エージェント | ファイル | 用途 |
|-------------|---------|------|
| issue-scanner | `agents/issue-scanner.md` | 状態分析と分類 |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/diff` | 個別Issueの詳細乖離分析 |
| `/issue/gaps` | scan結果を元にアクション実行 |
