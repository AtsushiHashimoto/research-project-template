# {{PROJECT_NAME}} プロジェクト設定

## プロジェクト概要

{{PROJECT_DESCRIPTION}}

**研究者**: {{RESEARCHER_NAME}}
**開始日**: {{START_DATE}}

---

## Issue-Driven ワークフロー

このプロジェクトはGitHub Issueを中心とした開発フローで進めます。

### 新規タスク開始時の手順

1. **まずGitHub Issueを作成**
   - 新たなタスクが指示されたら、最初にGitHub Issue を作成する
   - Issue には明確なタイトルと説明を記載
   - 適切なラベルを付ける（feature, bug, enhancement, research など）

2. **ブランチの作成**
   - Issue に対応するブランチを作成: `feature/ISSUE_ID-short-description` または `research/ISSUE_ID-description`
   - 例: `feature/5-add-dataset-loader`, `research/3-model-training`

3. **Git Worktree の使用（必須）**
   - 並行タスクでブランチがコンタミネーション（混入）しないよう、**必ず worktree を作成**して作業する
   - Worktree 作成例:
     ```bash
     git worktree add worktrees/issue5 feature/5-add-dataset-loader
     cd worktrees/issue5
     ```
   - 複数の Issue を並行して進める場合、それぞれ独立した worktree で作業する
   - **注意**: Dockerコンテナ内での開発に対応するため、worktreeは `worktrees/` ディレクトリ内に作成する

### 進捗報告のルール

- **途中経過は Issue のコメントに Markdown で報告**
  - コードを書いた後、コミット前に進捗を Issue に報告
  - 報告内容：
    - 完了した作業
    - 現在のブロッカー（あれば）
    - 次のステップ

### コミットのルール

- **指示があったときのみコミットする**
  - 自動的にコミットせず、明示的な指示を待つ
  - コミットメッセージには必ず Issue を参照: `Fixes #ISSUE_ID` または `Refs #ISSUE_ID`
  - Conventional Commits 形式を推奨:
    - `feat(scope): description` - 新機能
    - `fix(scope): description` - バグ修正
    - `docs(scope): description` - ドキュメント
    - `refactor(scope): description` - リファクタリング
    - `test(scope): description` - テスト追加

### プルリクエストのルール

- ブランチでの作業完了後、PR を作成
- PR タイトルに Issue 番号を含める
- PR 説明に `Closes #ISSUE_ID` を記載してリンク

---

## スキル一覧

### タスク管理

| スキル | 用途 |
|-------|------|
| `/start-task [説明]` | 新しいタスクを開始（Issue作成→ブランチ→Worktree） |
| `/branch-task [説明]` | 現在のWorktree内で子タスクを作成 |
| `/report-progress` | 現在の進捗をIssueに報告 |
| `/finish-task` | タスクを完了（レビュー→マージ→Issueクローズ） |

### コミット

| スキル | 用途 | Issueクローズ |
|-------|------|--------------|
| `/commit` | ローカルにコミットのみ | ❌ |
| `/commit push` | コミット＆プッシュ（途中保存） | ❌ |
| `/commit merge` | コミット＆マージ（タスク完了） | ✅ |

### Worktree管理

| スキル | 用途 |
|-------|------|
| `/worktree/init` | 初回セットアップ（共有データパス設定） |
| `/worktree/setup` | Worktreeにデータディレクトリを作成 |
| `/worktree/safe-remove` | Worktreeを安全に削除 |

---

## Git Worktree 管理

### Worktree 作成の標準パターン

```bash
# 新しい Issue #N のブランチと worktree を作成
git worktree add worktrees/issueN feature/N-description
cd worktrees/issueN
```

### 並行作業の例

```
{{PROJECT_NAME}}/                # メインリポジトリ
├── worktrees/                   # Worktree用ディレクトリ（.gitignore対象）
│   ├── issue5/                  # feature/5-description
│   ├── issue7/                  # research/7-description
│   └── issue9/                  # fix/9-description
├── data/
│   └── shared/                  # 共有データ（全worktreeからアクセス可能）
└── src/                         # メインブランチのソース
```

---

## Worktree データ保護

### 概要

Worktree削除時に重要データ（データセット、実験結果）が失われないよう、データディレクトリを以下のように分離します：

- **`data/shared/`**: 重要データ（全Worktreeで共有、削除時も保護）
- **`data/local/`**: 一時データ（Worktree削除時に一緒に削除）

### データの保存先

**重要データ（保存）:**
```bash
# データセット
mv large_dataset.json data/shared/datasets/

# 実験結果
mv experiment_results.csv data/shared/results/

# 学習済みモデル
mv best_model.pt data/shared/models/
```

**一時データ（削除OK）:**
```bash
# キャッシュ
mv preprocessed_batch.pkl data/local/cache/

# デバッグ出力
mv debug_images/ data/local/debug/
```

---

## 開発ガイドライン

### コード品質
- テストを書いてからコミット
- 新機能にはドキュメントを追加
- リファクタリング時は既存のテストが通ることを確認

### 研究ノート
- 実験結果は Issue に記録
- ハイパーパラメータの変更履歴を残す
- データセットのバージョン管理

### ブランチの命名規則
- `feature/ISSUE_ID-description` - 新機能
- `research/ISSUE_ID-description` - 研究・実験
- `fix/ISSUE_ID-description` - バグ修正
- `docs/ISSUE_ID-description` - ドキュメント

---

## 重要な注意事項

1. **常に worktree を使用**: メインディレクトリで直接作業しない
2. **Issue なしで作業しない**: すべてのタスクは Issue から開始
3. **進捗は Issue に記録**: コミット前に必ず報告
4. **明示的指示を待つ**: 自動コミットはしない
