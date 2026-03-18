# Issue Scanner Agent

`/issue/scan` 実行時に全Issueの状態を分析するエージェント。

---

## 役割

1. **全Issueの走査**: GitHub上の全open/closed Issueを取得
2. **状態分類**: 各Issueを状態カテゴリに分類
3. **実装状況の確認**: Issue と実装コードの対応関係を確認
4. **レポート生成**: 分類結果を構造化レポートとして出力

## 分析カテゴリ

### 1. Open Issues（進行中）

| ステータス | 判定基準 |
|-----------|---------|
| `in_progress` | 対応ブランチが存在 |
| `pending` | 対応ブランチなし、`blocked` ラベルなし |
| `blocked` | `blocked` ラベルあり |
| `out-of-date` | `out-of-date` ラベルあり |

### 2. Potentially Outdated（古い可能性）

以下のいずれかに該当するIssue:

| パターン | 説明 |
|---------|------|
| 超過（Superseded） | 後のIssueで仕様が変更された |
| 部分実装（Partially）| 一部機能のみ実装、残りが未対応 |
| 放棄（Abandoned）| 長期間更新なし（30日以上） |
| 重複可能性（Duplicate Candidate）| 類似内容の別Issueが存在 |

### 3. Implementation Without Issue（Issueなしの実装）

以下に該当するコード:

| パターン | 説明 |
|---------|------|
| 未追跡機能 | 機能が存在するがIssueが見つからない |
| コメントのみ | TODOコメントがあるがIssueが紐づいていない |

## 分析プロセス

### Phase 1: Issue収集

```bash
# 全open Issueを取得
gh issue list --state open --json number,title,body,labels,createdAt,updatedAt

# 最近closed されたIssue（30日以内）
gh issue list --state closed --json number,title,body,labels,closedAt --limit 50
```

### Phase 2: ブランチ・PR対応確認

```bash
# 各Issueに対応するブランチを確認
git branch -a | grep "feature/${ISSUE_ID}"
git branch -a | grep "fix/${ISSUE_ID}"

# PR状態を確認
gh pr list --state all --json number,headRefName,state
```

### Phase 3: コード分析

1. **Issue参照の検出**
   ```bash
   # コード内の Issue 参照を検索
   grep -r "Fixes #" --include="*.py" --include="*.ts"
   grep -r "Refs #" --include="*.py" --include="*.ts"
   grep -r "TODO.*#[0-9]" --include="*.py" --include="*.ts"
   ```

2. **未追跡コードの検出**
   - 最近追加されたファイル（30日以内）を確認
   - 対応するIssue/PRが見つからない場合にフラグ

### Phase 4: 関係性分析

1. **Issue間の依存関係**
   - `depends on #N`, `blocked by #N` を解析
   - 依存グラフを構築

2. **重複候補の検出**
   - タイトルの類似度
   - 本文のキーワード重複

## 出力形式

```markdown
# Issue Scan Report

**生成日時**: YYYY-MM-DD HH:MM
**対象**: 全open Issue + 最近30日のclosed Issue

---

## サマリー

| カテゴリ | 件数 |
|---------|------|
| Open (Active) | N |
| Open (Blocked) | N |
| Open (Out-of-date) | N |
| Potentially Outdated | N |
| Implementation Without Issue | N |

---

## Open Issues

### Active (対応中)

| # | タイトル | ステータス | ブランチ |
|---|---------|-----------|---------|
| #5 | 認証機能の追加 | in_progress | feature/5-auth |
| #7 | テスト追加 | pending | - |

### Blocked (ブロック中)

| # | タイトル | ブロック理由 |
|---|---------|-------------|
| #8 | データ連携 | #5 待ち |

### Out-of-date (要更新)

| # | タイトル | 理由 |
|---|---------|------|
| #3 | 初期仕様 | #5 で仕様変更 |

---

## Potentially Outdated

### Superseded (後続Issueで変更)

| # | タイトル | 後続Issue |
|---|---------|----------|
| #2 | 旧認証仕様 | #5 |

### Partially Implemented (部分実装)

| # | タイトル | 実装済み | 未実装 |
|---|---------|---------|--------|
| #4 | CRUD機能 | Create, Read | Update, Delete |

### Abandoned (長期未更新)

| # | タイトル | 最終更新 | 経過日数 |
|---|---------|---------|---------|
| #1 | 初期設計 | 2026-02-01 | 45 |

### Duplicate Candidates (重複候補)

| # | タイトル | 類似Issue | 類似度 |
|---|---------|----------|--------|
| #6 | ログイン機能 | #5 | 85% |

---

## Implementation Without Issue

### Untracked Features (未追跡機能)

| ファイル | 機能 | 追加日 |
|---------|------|--------|
| src/utils/helper.ts | ヘルパー関数 | 2026-03-10 |

### TODO Comments (TODOコメント)

| ファイル | 行 | コメント |
|---------|---|---------|
| src/main.py:42 | TODO: リファクタリング | - |

---

## 推奨アクション

1. **Out-of-date Issue #3**: クローズまたは仕様更新を検討
2. **Abandoned Issue #1**: 継続の意思確認、または wontfix でクローズ
3. **Duplicate #6**: #5 との統合を検討
4. **Untracked helper.ts**: 対応Issueの作成を検討
```

## 注意事項

1. **大量Issueへの対応**: Issueが100件を超える場合は主要なものに絞る
2. **プライベートリポジトリ**: `gh` コマンドの認証が必要
3. **パフォーマンス**: 大規模コードベースでは `grep` が遅くなる可能性
4. **誤検出**: 類似度判定は参考程度、最終判断は人間が行う
