---
description: Multi-agent review of current branch changes (多角的レビュー)
---

# Multi-Agent Review（多角的コードレビュー）

現在のブランチの変更内容を、6つの専門的な観点から並列にレビューします。

## 用途

- コミット前の品質確認
- `/commit-merge` 前のプリレビュー
- 設計判断の妥当性検証
- 仕様との整合性確認

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

### Step 2: Issue目的と仕様ファイルの確認

```bash
# Issue内容を取得して目的を把握
gh issue view "$ISSUE_ID" --json title,body

# 仕様ファイルの確認
SPEC_FILE=$(ls .claude/spec/issues/${ISSUE_ID}-*.md 2>/dev/null | head -1)
if [ -n "$SPEC_FILE" ]; then
  cat "$SPEC_FILE"
fi
```

### Step 3: 6つのサブエージェントを並列実行

**6つのサブエージェントを Task tool で並列に起動**し、それぞれ異なる観点でレビューを行います。

各サブエージェントには以下を渡します：
- `git diff main` の出力（変更内容）
- Issue のタイトルと本文（目的）
- 仕様ファイルの内容（存在する場合）
- 変更されたファイルの完全な内容

#### 3-1. アーキテクチャレビュー（Architecture Review）

Task tool で `subagent_type=general-purpose` を使用。

レビュー観点：
- **設計の妥当性**: 変更が既存のアーキテクチャパターンと整合しているか
- **単一情報源の原則（Single Source of Truth）**: 同じ情報が複数箇所で定義されていないか。修正時に複数箇所を変更する必要がないか
- **既存コードとの一貫性**: 命名規則、コーディングスタイルが統一されているか
- **過度な複雑性**: YAGNI原則に反した過剰設計がないか
- **依存関係**: 不要な依存の追加や循環依存がないか
- **ファイルサイズ**: 変更ファイルが肥大化していないか（行数順にチェック）

**ファイルサイズチェック**:
```bash
# 変更ファイルの行数を取得（大きい順）
git diff main --name-only | xargs wc -l 2>/dev/null | sort -rn | head -20
```

| 閾値 | 判定 |
|------|------|
| 300行以下 | ✅ OK |
| 300-500行 | ⚠️ 分割検討 |
| 500行超過 | ❌ 分割必須 |

超過ファイルについては以下を分析：
- 肥大化の原因（複数責務、コピペ、過剰な分岐）
- 分割案（責務ごとのファイル分割提案）
- 仕様ファイルの想定行数との比較

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
- **網羅性**: 全ての分岐パス、境界値、エラーケースがテストされているか
- **潜在的バグの検出力**: テストが以下のような細かいミスを検出できるか
  - int/float の型変換ミス
  - round/floor/ceil の使い分けミス
  - 文字列エンコーディングの問題
  - タイムゾーン関連のバグ
  - 浮動小数点の比較誤差
- **エッジケーステスト**: 空配列、null、0、負数、最大値でのテストがあるか
- **テストの独立性**: テスト間に不要な依存がないか
- **テスト不要な変更の判定**: 設定ファイルやドキュメントのみの変更など、テスト不要な場合は明示

#### 3-4. Fallbackチェッカー（Fallback Checker）

Task tool で `subagent_type=general-purpose` を使用。

**事前準備**: 仕様ファイルから「承認済みFallbackホワイトリスト」を読み込む。

レビュー観点：
コード内の全 if/switch/try-catch を走査し、以下をチェック：

- **else でデフォルト値返却**: `if x: return x else: return default`
- **switch/match の default で無視**: `case _: pass` or `default: break`
- **try-except で握りつぶし**: `except: pass` or `except: return None`
- **Optional unwrap でデフォルト**: `x.unwrap_or(default)` without logging
- **null合体演算子**: `x ?? default` without explicit design reason
- **空配列/空オブジェクトで続行**: `if not data: data = []` then continue processing

出力形式：
```markdown
## Fallback検出結果

### ✅ 承認済み（ホワイトリストにマッチ）
- `ファイル:行` - `パターン`

### 🔴 未承認（要修正）
- `ファイル:行` - `パターン`
  - ホワイトリストに該当なし
  - 推奨: [修正案]

### 🟡 新規fallback（要判断）
- `ファイル:行` - `パターン`
  - 計画時に想定されていなかった分岐
  - 許可する場合はホワイトリストに追加
```

#### 3-5. 仕様充足チェッカー（Spec Compliance Checker）

Task tool で `subagent_type=general-purpose` を使用。

**事前準備**: 仕様ファイルから「検証チェックリスト」を読み込む。

レビュー観点：
仕様ファイルの各チェック項目について、実装が満たしているか検証。

出力形式：
```markdown
## 仕様充足チェック結果

### ✅ 充足
- [x] チェック項目

### ❌ 未充足
- [ ] チェック項目
  - **現状**: [実装の状態]
  - **修正案**: [具体的な修正方法]

### ⚠️ 検証不能
- [ ] チェック項目
  - **理由**: [検証できない理由]
  - **推奨**: [検証可能にするための提案]
```

#### 3-6. ロジック検証チェッカー（Logic Verification Checker）

Task tool で `subagent_type=general-purpose` を使用。

レビュー観点：
- **ループの必要十分性**: for/while の対象が過不足なく処理されるか
  - 処理対象の範囲は正しいか
  - 必要なデータが漏れていないか
  - 不要なデータを処理していないか
- **条件分岐の網羅性**: if/switch/match で全ケースが考慮されているか
  - 抜けているケースはないか
  - 到達不能なコードはないか
- **off-by-oneエラー**: `<` vs `<=`、`range(n)` vs `range(n+1)` の検証
- **型変換の正確性**: int/float/round、文字列変換で精度が失われないか
- **空・境界の処理**: 空配列、0件、最大値でループが正しく動くか
- **早期終了の正当性**: break/continue/return が意図通りか
- **インデックスアクセス**: 配列/リストへのアクセスが範囲内か

出力形式：
```markdown
## ロジック検証結果

### 🔴 問題あり
- `ファイル:行` - [問題の説明]
  - **コード**: `該当コード`
  - **問題**: [具体的な問題点]
  - **修正案**: [修正方法]

### 🟡 要確認
- `ファイル:行` - [確認が必要な点]

### ✅ 問題なし
- ループ処理: N箇所確認済み
- 条件分岐: M箇所確認済み
```

### Step 4: レビュー結果の統合

6つのサブエージェントの結果を統合し、以下の形式で報告：

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

### 🚫 Fallback Check
[結果サマリー]
- ✅ 承認済み: N件
- ❌ 未承認: M件
- 🟡 新規: K件

### 📋 Spec Compliance
[結果サマリー]
- ✅ 充足: N件
- ❌ 未充足: M件
- ⚠️ 検証不能: K件

### 🔄 Logic Verification
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
3. 仕様ファイル `.claude/spec/issues/{issue_id}-*.md` を読み込み
4. **Task tool を6回並列に呼び出し**、各サブエージェントにレビュー指示を渡す
5. 結果を統合してユーザーに提示

**重要**: 6つのサブエージェントは必ず**並列**（同一メッセージ内で複数のTask tool呼び出し）で起動すること。

## Note

- `/commit-merge` のPhase 0（品質チェック）とは独立して実行可能
- より詳細なレビューが必要な場合にこのコマンドを使用
- `/commit-merge` は単体でも品質チェックを行うため、両方を実行する必要はない
- 仕様ファイルが存在しない場合、Fallbackチェッカーと仕様充足チェッカーは「仕様ファイルなし」と報告する
