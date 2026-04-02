$ cat review-integrity/SKILL.md 
---
description: Periodic codebase integrity and consistency review (定期的な実装整合性チェック)
---

# Review Integrity

コードベースの整合性・一貫性を定期的にレビューするスキル。
`/issue/auto` 完了後や大きな変更の後に実行推奨。

## Usage

```
/review-integrity              # 全チェック実行
/review-integrity --quick      # 高速チェックのみ（grep/静的解析）
/review-integrity --since #390 # 指定PR以降の変更に絞る
```

## チェック項目

### 1. Interface整合性
新規部分と既存部分のinterface設計に齟齬がないか。

- 関数シグネチャの型が呼び出し元と一致しているか
- TYPE_CHECKING import が正しく機能しているか
- Protocol/ABC の実装が全メソッドをカバーしているか
- config フィールドが定義箇所と使用箇所で一致しているか

### 2. 実装の一貫性
コーディングスタイル・パターンの統一。

- 同じ処理が複数箇所で異なる方法で実装されていないか（DRY違反）
- 命名規則の統一（lang vs language, session_id の扱い等）
- エラーハンドリングパターンの統一
- import スタイルの統一（TYPE_CHECKING の使い方）

### 3. 実装意図の明確性
コードの意図がドキュメントまたはコード自体から読み取れるか。

- 非自明な設計判断にコメントがあるか
- invariants.md に記載すべき暗黙の制約がないか
- マジックナンバー・ハードコーディングがないか
- `# TODO`, `# HACK`, `# FIXME` の棚卸し

### 4. デッドコード・孤立モジュール
使われていないコードが残存していないか。

- import されていないモジュール
- 呼び出されていない関数/クラス
- 渡されたが使われていないパラメータ
- `__init__.py` でexportされているが使用されていないシンボル

### 5. 配線の完全性
データが正しく末端まで届いているか。

- config に定義されたフィールドが実際にランタイムで使用されているか
- 引数として受け取ったが内部で参照されていないパラメータ
- イベントハンドラが登録されているがイベントが発火しないケース
- テストのモックが実際のインターフェースと乖離していないか

### 6. テストカバレッジの妥当性
変更に対してテストが追従しているか。

- 新規追加コードにテストがあるか
- 既存テストが変更後のインターフェースに追従しているか
- テストが実装をテストしているか（モックのテストになっていないか）

### 7. セキュリティ・依存関係
外部依存や入力処理の安全性。

- 新規依存が pyproject.toml に追加されているか
- 入力バリデーションが適切か（WebSocket入力、REST API入力）
- 機密情報がコードにハードコーディングされていないか

## 実行ワークフロー

### Phase 1: 並列調査（6 Explore エージェント）

以下の6エージェントを並列起動する。各エージェントには **判断根拠を含む詳細な分析** を求める。

| # | ID | 担当 | 出力ファイル名 |
|---|-----|------|---------------|
| 1 | structure | プロジェクト構造の探索 | `01-structure.md` |
| 2 | dead-code | デッドコード・未使用要素の検出 | `02-dead-code.md` |
| 3 | todo-magic | TODO/FIXME棚卸し・マジックナンバー | `03-todo-magic.md` |
| 4 | interface | Interface整合性チェック | `04-interface.md` |
| 5 | dry-naming | DRY違反・命名一貫性 | `05-dry-naming.md` |
| 6 | wiring-test | 配線完全性・テストカバレッジ | `06-wiring-test.md` |

各エージェントのプロンプトには以下を含める:
```
判断根拠を必ず記載すること。
- なぜその箇所を問題と判断したか
- 他の解釈の可能性を検討したか
- 深刻度の根拠（影響範囲、発生頻度、修正コスト）
```

### Phase 2: 結果保存

結果は `data/shared/integrity-reviews/` 配下にタイムスタンプ付きディレクトリで保存する。

```
data/shared/integrity-reviews/
├── latest -> 2026-04-02T1430    # 最新へのシンボリックリンク
├── 2026-04-02T1430/
│   ├── summary.md               # 統合レポート
│   ├── 01-structure.md
│   ├── 02-dead-code.md
│   ├── 03-todo-magic.md
│   ├── 04-interface.md
│   ├── 05-dry-naming.md
│   ├── 06-wiring-test.md
│   └── 07-discrepancy.md        # 前回との差分分析（初回は空）
├── 2026-04-02T1630/             # 同日2回目の実行
│   ├── ...
```

ディレクトリ名のフォーマット: `YYYY-MM-DDTHHMM`（ISO 8601ベース、秒は省略）

保存手順:
```bash
# タイムスタンプ生成
TIMESTAMP=$(date +"%Y-%m-%dT%H%M")
REVIEW_DIR="data/shared/integrity-reviews/${TIMESTAMP}"
mkdir -p "${REVIEW_DIR}"

# 各subagentの結果をファイルに書き出し（Write tool使用）
# ...

# latestシンボリックリンクを更新
ln -sfn "${TIMESTAMP}" data/shared/integrity-reviews/latest
```

### Phase 3: 差分分析（単調改善チェック）

前回の結果が存在する場合、**7番目のエージェント**を起動して差分を分析する。

```
Agent(subagent_type="Explore", prompt="
前回のレビュー結果: data/shared/integrity-reviews/{prev_timestamp}/
今回のレビュー結果: data/shared/integrity-reviews/{curr_timestamp}/

以下の観点で差分を分析せよ:

## 1. 問題の増減
- 解消された問題（前回あり→今回なし）: コード修正による改善か
- 新規発見（前回なし→今回あり）: 退行か、今回の分析精度向上か
- 継続中の問題: 未対応なのか、意図的に保留なのか

## 2. 判断品質の変化
同一コード箇所に対する評価が変わった場合:
- 深刻度の変更: より妥当な判断か、判断のブレか
- 分類の変更: より正確な分類か
- 見落とし/誤検出: 前回の見落としを今回発見 or 前回の誤検出を今回修正

## 3. 単調改善の判定
以下の基準で改善が単調的かを判定:
- [改善] 問題数が減少した
- [改善] 同一問題の深刻度評価がより正確になった
- [改善] 前回見落としていた問題を発見した
- [退行] 前回発見した問題を今回見落とした
- [退行] 誤検出が増加した
- [横ばい] 問題の総数と質が同程度

最終判定: IMPROVING / STABLE / REGRESSING
理由を3行以内で記載。
")
```

### Phase 4: GitHub Issue投稿

統合レポートを GitHub Issue として投稿する。

```bash
gh issue create \
  --title "Integrity Review: ${TIMESTAMP}" \
  --label "review-integrity" \
  --body-file "${REVIEW_DIR}/summary.md"
```

Issue本文の構成:
```markdown
# Integrity Review Report

**実行日時**: YYYY-MM-DDTHH:MM
**対象**: 全コードベース / PR #XXX 以降
**前回との比較**: IMPROVING / STABLE / REGRESSING

## サマリー

| 深刻度 | 件数 | 前回比 |
|--------|------|--------|
| Critical | N | +0/-0 |
| High | N | +1/-2 |
| Medium | N | +0/-1 |
| Low | N | +3/-0 |

## 発見事項

### Critical (N件)
...

### High (N件)
| # | ファイル | 問題 | 修正案 | 判断根拠 |
|---|---------|------|--------|---------|

### Medium (N件)
...

### Low (N件)
...

## 差分分析（前回比）

### 解消された問題
- ...

### 新規発見
- ...

### 判断品質の変化
- ...

## Subagent詳細レポート
各subagentの詳細な分析結果は以下のファイルに保存:
- `data/shared/integrity-reviews/{TIMESTAMP}/01-structure.md`
- ...（各ファイルへのリンク）

## アクション
- [ ] Issue #XXX 作成: ...
- [ ] Issue #YYY 作成: ...
```

## Phase 5: 修正Issueの作成

レビューで発見された問題は、個別の GitHub Issue として作成し `/issue/auto` 等で修正する。
`/review-integrity` 自体は診断に徹し、修正は Issue-Driven ワークフローで行う。

### Issue化のグルーピングポリシー

発見事項を1:1でIssueにすると粒度が細かくなりすぎる。以下の基準でグルーピングする:

1. **同一種別・同一動機の問題はまとめる**
   - 例: DRY違反が3箇所 → 「DRY違反の解消」として1 Issue
   - 例: テスト不在が2モジュール → 「テスト追加」として1 Issue
2. **バグ修正とそのテスト追加はセットにする**
   - 例: `_notify()` 漏れ修正 + `config_manager` テスト追加 → 1 Issue
3. **影響範囲が広い命名変更は独立Issueにする**
   - 例: `lang` → `language` 統一は多数ファイルに影響するため単独 Issue
4. **目安: 発見9件 → Issue 3〜5件 程度**
   - 1 Issue あたりの作業量が 1 PR で収まるサイズを目指す

### Issue作成テンプレート

```bash
gh issue create \
  --title "fix: {問題の要約}" \
  --label "{bug|refactor|test}" \
  --body "$(cat <<'EOF'
## 背景
Integrity Review {TIMESTAMP} で検出 (#{review_issue_number})

## 対象
- `file1.py:L100` - 問題の説明
- `file2.py:L200` - 問題の説明

## 修正方針
...

## 完了条件
- [ ] 修正実装
- [ ] テスト追加/更新
- [ ] CI pass
EOF
)"
```

## 出力形式（summary.md）

summary.md は上記 Issue 本文と同一内容を保存する。

## 自動実行のトリガー

以下のタイミングで実行を推奨:
- `/issue/cycle` 完了後
- 5件以上の PR がマージされた後
- 大規模リファクタリング後
- ユーザーから明示的に依頼された時
