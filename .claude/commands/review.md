---
description: Multi-agent review of current branch changes (多角的レビュー)
---

# Multi-Agent Review（多角的コードレビュー）

現在のブランチの変更内容を、複数の専門的な観点から並列にレビューします。

## 用途

- コミット前の品質確認
- `/commit-merge` 前のプリレビュー
- 設計判断の妥当性検証

## Workflow

### Step 1: 変更内容の収集

まず現在のブランチの変更を収集します：

```bash
# Issue番号の取得
BRANCH=$(git branch --show-current)
ISSUE_ID=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# 変更の範囲を確認
git diff main --stat
git diff main --name-only
git log main..HEAD --oneline
```

### Step 2: Issue目的の確認

```bash
# Issue内容を取得して目的を把握
gh issue view "$ISSUE_ID" --json title,body
```

### Step 3: 並列サブエージェントレビュー

**3つのサブエージェントを Task tool で並列に起動**し、それぞれ異なる観点でレビューを行います。

各サブエージェントには以下を渡します：
- `git diff main` の出力（変更内容）
- Issue のタイトルと本文（目的）
- 変更されたファイルの完全な内容

#### 3-1. アーキテクチャレビュー（Architecture Review）

Task tool で `subagent_type=general-purpose` を使用。

レビュー観点：
- **設計の妥当性**: 変更が既存のアーキテクチャパターンと整合しているか
- **単一情報源の原則（Single Source of Truth）**: 同じ情報が複数箇所で定義されていないか。修正時に複数箇所を変更する必要がないか
- **既存コードとの一貫性**: 命名規則、コーディングスタイルが統一されているか
- **過度な複雑性**: YAGNI原則に反した過剰設計がないか
- **依存関係**: 不要な依存の追加や循環依存がないか

#### 3-2. リスクレビュー（Risk Review）

Task tool で `subagent_type=general-purpose` を使用。

レビュー観点：
- **対症療法的修正の検出（重要）**: 想定される挙動と異なる振る舞いに対して、挙動を上書きする形での修正を検出。このような修正は保守性を低下させるため禁止
  - 例: 根本原因を修正せず、出力を後から加工する処理
  - 例: バグの原因を直さず、条件分岐で回避する処理
- **セキュリティ**: 機密情報の漏洩、インジェクション脆弱性、安全でないデシリアライゼーション
- **エッジケース**: 境界値、null/undefined、空配列、並行処理の問題
- **データ保護**: 重要データが `data/shared/` に保存され、Worktree削除時に失われない設計か
- **ハードコーディング**: マジックナンバー、固定パス、環境依存値が設定に抽出されているか
- **ポータビリティ**: 他の環境でも動作するか

#### 3-3. テストレビュー（Test Review）

Task tool で `subagent_type=general-purpose` を使用。

レビュー観点：
- **テストカバレッジ**: 変更された機能に対するテストが存在するか
- **テスト品質**: テストが実際に意味のある検証をしているか（trivialなアサーションでないか）
- **エッジケーステスト**: 境界値やエラーケースのテストがあるか
- **テストの独立性**: テスト間に不要な依存がないか
- **テスト不要な変更の判定**: 設定ファイルやドキュメントのみの変更など、テスト不要な場合は明示

### Step 4: レビュー結果の統合

3つのサブエージェントの結果を統合し、以下の形式で報告：

```markdown
## 🔍 Multi-Agent Review Results

### 📐 Architecture Review
[結果サマリー]
- ✅ / ⚠️ / ❌ 各項目の判定

### 🛡️ Risk Review
[結果サマリー]
- ✅ / ⚠️ / ❌ 各項目の判定

### 🧪 Test Review
[結果サマリー]
- ✅ / ⚠️ / ❌ 各項目の判定

### 📋 Summary
- **Critical Issues**: [即座に修正が必要な問題]
- **Warnings**: [改善を推奨する問題]
- **Approved**: [問題なしの項目]

### 💡 Recommendations
[具体的な改善提案]
```

### Step 5: ユーザーへの提示

レビュー結果を提示し、以下を確認：
- Critical Issues がある場合: 修正を提案
- Warnings のみの場合: 修正するか進めるか確認
- 問題なしの場合: `/commit-merge` への進行を提案

## Implementation

1. `git diff main` で変更内容を取得
2. `gh issue view` でIssue目的を取得
3. **Task tool を3回並列に呼び出し**、各サブエージェントにレビュー指示を渡す
4. 結果を統合してユーザーに提示

**重要**: 3つのサブエージェントは必ず**並列**（同一メッセージ内で複数のTask tool呼び出し）で起動すること。

## Note

- `/commit-merge` のPhase 0（品質チェック）とは独立して実行可能
- より詳細なレビューが必要な場合にこのコマンドを使用
- `/commit-merge` は単体でも品質チェックを行うため、両方を実行する必要はない
