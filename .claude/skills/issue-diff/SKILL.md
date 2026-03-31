---
description: Analyze gap between issue spec and implementation (Issue乖離分析)
argument-hint: <issue_id>
---

# Issue Diff Analyzer

単一IssueのHEAD実装との乖離を分析します。

## Usage

```
/issue/diff 5           # Issue #5 の乖離分析
/issue/diff #5          # # 付きも可
/issue/diff 5 --verbose # 詳細出力
```

## Output

分析結果は以下のカテゴリに分類されます:

- **Implemented**: 実装済みの機能
- **Missing**: 未実装の機能
- **Changed**: 後続変更で仕様が変わった機能
- **Extra**: Issue記載なしの追加実装

最終的に **Verdict** として全体判定を出力します。

## Workflow

### Phase 1: Issue情報取得

1. **Issue本文の取得**
   ```bash
   ISSUE_ID="${ARGUMENTS//[^0-9]/}"
   gh issue view $ISSUE_ID --json number,title,body,labels,comments,createdAt,updatedAt
   ```

2. **関連PRの取得**
   ```bash
   gh pr list --search "fixes #${ISSUE_ID}" --state all --json number,title,state,mergedAt,headRefName
   ```

3. **仕様ファイルの確認**
   ```bash
   ls .claude/spec/issues/${ISSUE_ID}-*.md 2>/dev/null
   ```

### Phase 2: 実装コード特定

1. **コミット履歴検索**
   ```bash
   git log --all --grep="#${ISSUE_ID}" --format="%h %s" | head -20
   ```

2. **ブランチ確認**
   ```bash
   git branch -a --list "*/${ISSUE_ID}-*"
   ```

3. **コード内参照検索**
   ```bash
   grep -r "Refs #${ISSUE_ID}" --include="*.py" --include="*.ts" -l
   grep -r "Fixes #${ISSUE_ID}" --include="*.py" --include="*.ts" -l
   ```

### Phase 3: 乖離分析

**issue-diff-analyzer エージェントを使用**:

```
Task(subagent_type="general-purpose", prompt="
agents/issue-diff-analyzer.md の定義に従って、Issue #${ISSUE_ID} の乖離分析を行ってください。

## Issue情報
${ISSUE_DATA}

## 関連PR
${PR_DATA}

## 仕様ファイル（存在する場合）
${SPEC_FILE_CONTENT}

## コミット履歴
${COMMIT_LOG}

## 分析指示
1. Issue本文から要件を抽出
2. 各要件に対応する実装を特定
3. 実装済み/未実装/変更済み/追加実装 に分類
4. Verdict を判定
5. 推奨アクションを提示

出力は agents/issue-diff-analyzer.md の出力形式に従ってください。
")
```

### Phase 4: レポート出力

分析結果を Markdown 形式で出力。
`--output` オプション指定時はファイルに保存。

## Verdict Types

| Verdict | 説明 | 推奨アクション |
|---------|------|--------------|
| `FULLY_IMPLEMENTED` | 全要件が実装済み | Issueクローズ可 |
| `PARTIALLY_IMPLEMENTED` | 一部未実装 | 残作業のIssue作成 |
| `SPEC_CHANGED` | 仕様が古い | Issue更新または out-of-date |
| `NOT_STARTED` | 未着手 | 作業開始 |
| `OVER_IMPLEMENTED` | 追加実装あり | ドキュメント/Issue更新 |

## Options

| オプション | 説明 |
|-----------|------|
| `--verbose` | 詳細な分析結果を出力 |
| `--output FILE` | 結果をファイルに出力 |
| `--json` | JSON形式で出力 |
| `--suggest-issues` | 推奨Issue案を含める |

## Agent References

| エージェント | ファイル | 用途 |
|-------------|---------|------|
| issue-diff-analyzer | `agents/issue-diff-analyzer.md` | 乖離分析ロジック |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/scan` | 全Issueのスキャン |
| `/issue/gaps` | 乖離を元にアクション実行 |
