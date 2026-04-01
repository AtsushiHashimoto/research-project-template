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

### Phase 3.5: Dependency Check (Issue作成前)

Issue作成前に、既存のOpen Issueとの依存関係を自動検出します。

```bash
# Open Issueの情報を取得
OPEN_ISSUES=$(gh issue list --state open --json number,title,labels,body)

# 新規Issue候補ごとに依存関係をチェック
for NEW_ISSUE in $NEW_ISSUE_CANDIDATES; do
  BLOCKED_BY=""
  RELATED=""

  # 1. 同じファイルを編集中のin-progress Issueをチェック
  for OPEN_ISSUE in $OPEN_ISSUES; do
    # in-progressラベルがあるか確認
    if echo "$OPEN_ISSUE" | jq -r '.labels[].name' | grep -q "in-progress"; then
      ISSUE_NUM=$(echo "$OPEN_ISSUE" | jq -r '.number')

      # 関連ブランチのworktreeで編集中のファイルを取得
      BRANCH_NAME=$(gh issue view $ISSUE_NUM --json body -q '.body' | grep -oP 'feature/\d+-\S+' | head -1)
      if [ -n "$BRANCH_NAME" ]; then
        # worktreeの変更ファイルを確認
        MODIFIED_FILES=$(git -C .worktrees/issue${ISSUE_NUM} diff --name-only 2>/dev/null || echo "")

        # 新規Issueが同じファイルに影響するかチェック
        for FILE in $NEW_ISSUE_TARGET_FILES; do
          if echo "$MODIFIED_FILES" | grep -q "$FILE"; then
            BLOCKED_BY="$BLOCKED_BY #$ISSUE_NUM"
            break
          fi
        done
      fi
    fi
  done

  # 2. 関連するParent Issueをチェック（タイトル・本文の類似度）
  for OPEN_ISSUE in $OPEN_ISSUES; do
    ISSUE_TITLE=$(echo "$OPEN_ISSUE" | jq -r '.title')
    if [[ "$NEW_ISSUE_TITLE" == *"$ISSUE_TITLE"* ]] || \
       [[ "$NEW_ISSUE_BODY" == *"#$(echo "$OPEN_ISSUE" | jq -r '.number')"* ]]; then
      RELATED="$RELATED #$(echo "$OPEN_ISSUE" | jq -r '.number')"
    fi
  done

  # 3. 依存関係情報を新規Issue本文に追加
  if [ -n "$BLOCKED_BY" ]; then
    NEW_ISSUE_BODY="$NEW_ISSUE_BODY

## 関係
- Blocked by:$BLOCKED_BY (同じファイルを編集中)
$( [ -n \"$RELATED\" ] && echo \"- Related:$RELATED\" )"

    # blockedラベルも追加
    ADDITIONAL_LABELS="$ADDITIONAL_LABELS,blocked"
  elif [ -n "$RELATED" ]; then
    NEW_ISSUE_BODY="$NEW_ISSUE_BODY

## 関係
- Related:$RELATED"
  fi
done
```

**チェック項目**:

| チェック | 条件 | アクション |
|---------|------|-----------|
| ファイル競合 | in-progress Issueが同じファイルを編集中 | `Blocked by: #N` + `blocked`ラベル |
| Parent関係 | 新規Issueの内容が既存Issueの一部 | `Parent: #N` |
| 関連Issue | タイトルや本文に既存Issue番号を含む | `Related: #N` |

### Phase 3.6: ユーザーアクション必要の判定

作成予定のIssueがユーザーによる確認・検証を必要とするかを判定します。

```
Task(subagent_type="general-purpose", prompt="
以下のIssue候補について、ユーザーアクションが必要かどうかを判定してください。

## Issue候補
${NEW_ISSUE_CANDIDATES}

## 判定基準

### user-action ラベルが必要なケース
- 実ハードウェアでの動作確認が必要
- 本番環境/実運用環境での検証が必要
- 外部サービスとの連携テストが必要
- ユーザーの判断・承認が必要な機能
- UIの見た目・使い勝手の確認が必要

### user-action ラベルが不要なケース
- コード実装のみで完結
- ユニットテスト/統合テストで検証可能
- Mock/Stubで代替可能

## 出力形式
各Issue候補について:
- Issue ID/タイトル
- user-action: true/false
- 理由
")
```

判定結果を `REQUIRES_USER_ACTION` リストに追加します。

### Phase 4: Create

不足分のIssueを作成します。

#### 4-1: Missing機能のIssue

`PARTIALLY_IMPLEMENTED` のIssueから残作業を抽出してIssue作成:

```bash
# ラベルの決定
LABELS="feature"
if [ -n "$BLOCKED_BY" ]; then
  LABELS="${LABELS},blocked"
fi
if echo "$REQUIRES_USER_ACTION" | grep -q "$MISSING_FEATURE"; then
  LABELS="${LABELS},user-action"
  USER_ACTION_NOTE="
*⚠️ user-action: ユーザーによる確認・検証が必要です*"
else
  USER_ACTION_NOTE=""
fi

gh issue create \
  --title "feat: ${MISSING_FEATURE}" \
  --body "## 概要

${PARENT_ISSUE} で未実装だった機能を実装します。

## 背景

${PARENT_ISSUE_TITLE} の一部として計画されていましたが、実装されていませんでした。

## 関係
- Parent: #${PARENT_ISSUE_ID}
${BLOCKED_BY:+- Blocked by: ${BLOCKED_BY} (Phase 3.5で検出)}
${RELATED:+- Related: ${RELATED}}

## タスク

${TASK_DESCRIPTION}

---
*このIssueは /issue/gaps により自動生成されました*${USER_ACTION_NOTE}" \
  --label "$LABELS"
```

#### 4-2: 未追跡実装のIssue

Issueなしで実装されたコードに対するドキュメントIssueを作成:

```bash
# ラベルの決定
LABELS="docs"
if [ -n "$BLOCKED_BY" ]; then
  LABELS="${LABELS},blocked"
fi
if echo "$REQUIRES_USER_ACTION" | grep -q "$UNTRACKED_FEATURE"; then
  LABELS="${LABELS},user-action"
  USER_ACTION_NOTE="
*⚠️ user-action: ユーザーによる確認・検証が必要です*"
else
  USER_ACTION_NOTE=""
fi

gh issue create \
  --title "docs: ${UNTRACKED_FEATURE} のドキュメント作成" \
  --body "## 概要

以下のコードがIssueなしで実装されていることが検出されました。

## 対象コード

- ${FILE_PATH}

${BLOCKED_BY:+## 関係
- Blocked by: ${BLOCKED_BY} (Phase 3.5で検出)
${RELATED:+- Related: ${RELATED}}
}

## タスク

- [ ] 機能の目的を確認
- [ ] ドキュメントを作成
- [ ] 必要に応じてリファクタリング

---
*このIssueは /issue/gaps により自動生成されました*${USER_ACTION_NOTE}" \
  --label "$LABELS"
```

#### 4-3: ユーザーアクションIssueの通知

`user-action` ラベル付きIssueが作成された場合、`/qa/ask` でユーザーに通知:

```bash
if [ -n "$USER_ACTION_ISSUES" ]; then
  /qa/ask --type deferred "## 📋 ユーザー対応Issueが作成されました（/issue/gaps）

以下のIssueはユーザーによる確認・検証が必要です:

${USER_ACTION_ISSUES}

これらのIssueには \`user-action\` ラベルが付いており、\`/issue/auto\` ではスキップされます。
確認完了後、ラベルを外すか Issue をクローズしてください。"
fi
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

## Issue作成（自動処理可能）

| 新Issue | タイトル | Parent | 種類 |
|---------|---------|--------|------|
| #10 | パスワードリセット実装 | #5 | feature |
| #11 | helper.ts ドキュメント | - | docs |

## Issue作成（ユーザーアクション必要）

以下のIssueはユーザーによる確認・検証が必要です。`user-action` ラベル付き。

| 新Issue | タイトル | 必要なアクション |
|---------|---------|-----------------|
| #12 | validation: API統合テスト | 実APIサーバーでの動作確認 |

⚠️ これらのIssueは `/issue/auto` でスキップされます。
ユーザーが確認完了後、`user-action` ラベルを外すか Issue をクローズしてください。

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
5. **依存関係自動検出**: Issue作成前にOpen Issueとの競合をチェックし、`blocked`ラベルと依存関係を自動付与
6. **user-action 自動判定**: ユーザー確認が必要なIssueを自動検出し、`user-action`ラベルと`/qa/ask`通知を付与

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
