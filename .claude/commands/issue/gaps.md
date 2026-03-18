---
description: Detect gaps, label outdated issues, and create missing issues (乖離検出・Issue作成)
---

# Issue Gap Filler

scan + diff を統合し、乖離を検出してアクションを実行します。

## Usage

```
/issue/gaps              # 全Issueを分析してギャップを解消
/issue/gaps --dry-run    # 実際の変更は行わず、計画のみ表示
/issue/gaps --label-only # ラベル付与のみ（Issue作成しない）
```

## Actions

このスキルは以下のアクションを実行します:

1. **out-of-date ラベル付与**: 古いIssueにラベルを付与
2. **gap-fixed ラベル付与**: 乖離が解消されたIssueにラベルを付与
3. **不足分Issue作成**: 未追跡の実装やMissing機能のIssueを作成
4. **コメント追記**: 状況説明をIssueコメントに追記

## Workflow

### Phase 1: Scan

`/issue/scan` 相当の処理を実行し、全Issueの状態を把握します。

```
Task(subagent_type="general-purpose", prompt="
/issue/scan を実行し、全Issueの状態を把握してください。

出力形式:
- Open Issues リスト
- Potentially Outdated リスト
- Implementation Without Issue リスト
")
```

### Phase 2: Analyze

各Issueに対して `/issue/diff` 相当の分析を実行します。

```
# 各open Issueに対して並列実行可能
for ISSUE_ID in $OPEN_ISSUES; do
  Task(subagent_type="general-purpose", prompt="
  /issue/diff ${ISSUE_ID} を実行し、乖離分析レポートを生成してください。
  ")
done
```

**分析結果の集約**:

| Verdict | 対象Issue | アクション |
|---------|----------|-----------|
| SPEC_CHANGED | #3, #5 | out-of-date ラベル付与 |
| PARTIALLY_IMPLEMENTED | #7 | 残作業Issue作成 |
| NOT_STARTED | #9 | 状態確認（放棄？ブロック？） |
| FULLY_IMPLEMENTED | #10 | gap-fixed ラベル付与（元out-of-dateの場合） |

### Phase 3: Label

#### out-of-date ラベル付与

古いIssueに `out-of-date` ラベルを付与します。

```bash
for ISSUE_ID in $OUTDATED_ISSUES; do
  # ラベル付与
  gh issue edit $ISSUE_ID --add-label "out-of-date"

  # 理由をコメント
  gh issue comment $ISSUE_ID --body "## out-of-date

このIssueは以下の理由で out-of-date とマークされました:

### 理由
${REASON}

### 関連Issue/PR
${RELATED}

### 推奨アクション
- [ ] Issue内容を更新して out-of-date ラベルを外す
- [ ] クローズして新規Issueを作成
- [ ] wontfix としてクローズ

---
*このコメントは /issue/gaps により自動生成されました*"
done
```

#### gap-fixed ラベル付与

乖離が解消されたIssueに `gap-fixed` ラベルを付与します。

```bash
for ISSUE_ID in $FIXED_ISSUES; do
  # out-of-date を外して gap-fixed を付与
  gh issue edit $ISSUE_ID --remove-label "out-of-date" --add-label "gap-fixed"

  # コメント
  gh issue comment $ISSUE_ID --body "## gap-fixed

このIssueの乖離が解消されました。

### 解消内容
${FIX_SUMMARY}

### 関連Issue/PR
${RELATED}

---
*このコメントは /issue/gaps により自動生成されました*"
done
```

### Phase 4: Create

不足分のIssueを作成します。

#### 4-1: Missing機能のIssue

`PARTIALLY_IMPLEMENTED` のIssueから残作業を抽出してIssue作成:

```bash
gh issue create \
  --title "feat: ${MISSING_FEATURE}" \
  --body "## 概要

${PARENT_ISSUE} で未実装だった機能を実装します。

## 背景

${PARENT_ISSUE_TITLE} の一部として計画されていましたが、実装されていませんでした。

## 関係
- Parent: #${PARENT_ISSUE_ID}

## タスク

${TASK_DESCRIPTION}

---
*このIssueは /issue/gaps により自動生成されました*" \
  --label "feature"
```

#### 4-2: 未追跡実装のIssue

Issueなしで実装されたコードに対するドキュメントIssueを作成:

```bash
gh issue create \
  --title "docs: ${UNTRACKED_FEATURE} のドキュメント作成" \
  --body "## 概要

以下のコードがIssueなしで実装されていることが検出されました。

## 対象コード

- ${FILE_PATH}

## タスク

- [ ] 機能の目的を確認
- [ ] ドキュメントを作成
- [ ] 必要に応じてリファクタリング

---
*このIssueは /issue/gaps により自動生成されました*" \
  --label "docs"
```

### Phase 5: Report

実行結果のサマリーを出力します。

```markdown
# /issue/gaps 実行結果

**実行日時**: YYYY-MM-DD HH:MM

---

## ラベル付与

### out-of-date

| Issue | タイトル | 理由 |
|-------|---------|------|
| #3 | 初期仕様 | #5 で仕様変更 |
| #5 | 認証機能 | 部分的に別実装 |

### gap-fixed

| Issue | タイトル | 解消内容 |
|-------|---------|---------|
| #8 | API設計 | PR #15 で修正 |

## Issue作成

| 新Issue | タイトル | Parent | 種類 |
|---------|---------|--------|------|
| #10 | パスワードリセット実装 | #5 | feature |
| #11 | helper.ts ドキュメント | - | docs |

## スキップ

以下のIssueは out-of-date のためスキップされます:
- #3: 初期仕様
- #5: 認証機能（部分）

次回の `/issue/auto` ではこれらはスキップされます。
out-of-date ラベルを手動で外せば再度対象になります。

---

## 次のステップ

1. 作成されたIssue (#10, #11) を確認
2. 必要に応じて詳細を追記
3. `/issue/auto 10 11` で自動処理
```

## Options

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 実際の変更は行わず、計画のみ表示 |
| `--label-only` | ラベル付与のみ（Issue作成しない） |
| `--create-only` | Issue作成のみ（ラベル付与しない） |
| `--include-closed` | closedのIssueも分析対象に含める |

## Safety Features

1. **dry-run モード**: 実際の変更前に計画を確認可能
2. **ユーザー確認**: Issue作成前に確認を求める（デフォルト）
3. **自動生成マーク**: 自動生成コメント/Issueには明示的なマークを付与
4. **ロールバック可能**: ラベルは手動で外せる、Issueはクローズ可能

## Agent References

| エージェント | ファイル | 用途 |
|-------------|---------|------|
| issue-scanner | `agents/issue-scanner.md` | Phase 1 スキャン |
| issue-diff-analyzer | `agents/issue-diff-analyzer.md` | Phase 2 分析 |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue/scan` | 個別にスキャンを実行 |
| `/issue/diff` | 個別に乖離分析を実行 |
| `/issue/auto` | 作成されたIssueを自動処理 |
| `/issue/cycle` | gaps + auto のループ実行 |
