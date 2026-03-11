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

### Issue管理

| スキル | 用途 |
|-------|------|
| `/issue/start [説明]` | 新しいタスクを開始（Issue作成→ブランチ→Worktree） |
| `/issue/branch [説明]` | 現在のWorktree内で子タスクを作成 |
| `/issue/report` | 現在の進捗をIssueに報告 |
| `/issue/finish` | タスクを完了（レビュー→マージ→Issueクローズ） |

### コミット

| スキル | 用途 | Issueクローズ |
|-------|------|--------------|
| `/commit` | ローカルにコミットのみ | ❌ |
| `/commit/push` | コミット＆プッシュ（途中保存） | ❌ |
| `/commit/merge` | コミット＆マージ（タスク完了） | ✅ |

### レビュー

| スキル | 用途 |
|-------|------|
| `/review` | 多角的コードレビュー（3つのサブエージェントで並列レビュー） |

### テンプレート管理

| スキル | 用途 |
|-------|------|
| `/template/sync` | テンプレートの最新更新を取り込み |
| `/template/contribute` | テンプレートへの改善PRを作成 |

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
- **対症療法的修正の禁止**: 想定される挙動と異なる振る舞いに対して、挙動を上書きする形での修正は保守性を低下させるため禁止。根本原因を特定し修正すること
- **単一情報源の原則（Single Source of Truth）**: 同じ情報を複数箇所で定義しない。修正時に複数箇所を変更する必要がない設計にすること

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
5. **ルールは絶対**: このファイルに記載された全てのルール、スキルで定義されたワークフローは必ず従う
6. **省略・逸脱する前に確認**: ルールから外れる行為をする場合は、事前に一言ユーザーに確認を取る。自己判断で「不要」「単純だから省略」と決めない

---

## オプション機能の設定

### Ollama（ローカルLLM）

Ollamaのモデル永続化は事前設定済み（`data/shared/ollama_models/`）。使用するにはDockerfileにインストールコマンドを追加：

```dockerfile
# .devcontainer/Dockerfile に追加
RUN curl -fsSL https://ollama.com/install.sh | sh
```

コンテナ再ビルド後、以下で使用可能：
```bash
ollama serve &          # サーバー起動
ollama pull llama3.2    # モデルダウンロード
ollama run llama3.2     # 実行
```

### Claude Code認証

認証情報はbind mountで永続化済み。初回のみ `claude` を実行して認証。コンテナ再ビルド後も自動的に維持される。

---

## ドキュメント原則

### What vs How

- **README（What）**: このプロジェクトは何か、何ができるか、何が含まれているか
- **CLAUDE.md（How）**: どうやって作業するか、どういうルールで進めるか

### 変更時の注意

- 手順やルールの追加・変更は CLAUDE.md に記載
- プロジェクト概要やセットアップ手順は README に記載
- 同じ情報を両方に書かない（Single Source of Truth）
