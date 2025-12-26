# Research Project Template

Claude Code を活用した研究プロジェクト用テンプレートです。

## 特徴

- **Issue駆動開発**: GitHub Issueを中心としたワークフロー
- **Git Worktree管理**: 並行タスクを独立したディレクトリで管理
- **データ保護**: 重要データとWorktreeの分離
- **Claude Code統合**: カスタムスキルによる自動化

## セットアップ

### 1. テンプレートからリポジトリを作成

```bash
# このテンプレートをコピー
git clone https://github.com/YOUR_USERNAME/research-project-template.git my-project
cd my-project

# セットアップスクリプトを実行
chmod +x setup.sh
./setup.sh "My Project Name" "Project description" "Your Name"
```

### 2. GitHubリポジトリを作成

```bash
gh repo create my-project --public
git remote add origin https://github.com/YOUR_USERNAME/my-project.git
git push -u origin main
```

### 3. 開発環境を起動

VS Code で Dev Container を使用する場合:
1. VS Code で プロジェクトを開く
2. "Reopen in Container" を選択
3. Claude Code を起動: `claude`

## ディレクトリ構成

```
my-project/
├── .claude/
│   ├── CLAUDE.md          # プロジェクト設定・ワークフロー定義
│   ├── commands/          # カスタムスキル（コマンド）
│   │   ├── start-task.md
│   │   ├── commit.md
│   │   ├── commit-push.md
│   │   ├── commit-merge.md
│   │   ├── finish-task.md
│   │   ├── report-progress.md
│   │   └── branch-task.md
│   ├── skills/            # Worktree管理スキル
│   │   ├── worktree-init/
│   │   ├── worktree-setup/
│   │   └── worktree-safe-remove/
│   └── worktree-config.json
├── .devcontainer/
│   ├── devcontainer.json  # Dev Container設定
│   └── Dockerfile
├── data/
│   └── shared/            # 共有データ（Worktree間で共有）
├── worktrees/             # Worktree用ディレクトリ（.gitignore対象）
└── src/                   # ソースコード
```

## ワークフロー

### 新しいタスクを開始

```bash
# Claude Code を起動
claude

# タスクを開始
/start-task データセットの前処理を実装
```

これにより:
1. GitHub Issue が作成される
2. ブランチが作成される（例: `feature/1-dataset-preprocessing`）
3. Worktree が作成される（例: `worktrees/issue1`）

### 途中で保存

```bash
/commit push
```

- 変更をコミット＆プッシュ
- Issueは開いたまま
- Worktreeも残る

### タスクを完了

```bash
/finish-task
```

これにより:
1. 品質レビューを実施
2. PR を作成
3. マージ
4. Issue をクローズ
5. Worktree を削除

## カスタムスキル一覧

| スキル | 用途 |
|-------|------|
| `/start-task [説明]` | 新しいタスクを開始 |
| `/branch-task [説明]` | 子タスクを作成（同じWorktree内） |
| `/report-progress` | 進捗をIssueに報告 |
| `/commit` | ローカルにコミット |
| `/commit push` | コミット＆プッシュ（途中保存） |
| `/commit merge` | コミット＆マージ（タスク完了） |
| `/finish-task` | タスクを完了（= `/commit merge`） |

## データ管理

### 重要データ（保護される）

`data/shared/` に保存:
- データセット
- 実験結果
- 学習済みモデル

### 一時データ（削除OK）

`data/local/` に保存:
- キャッシュ
- デバッグ出力
- 一時ファイル

## カスタマイズ

### プロジェクト固有の設定

`.claude/CLAUDE.md` を編集してプロジェクト固有のルールを追加できます。

### Dev Container

`.devcontainer/` を編集して開発環境をカスタマイズできます:
- ベースイメージの変更
- 追加パッケージのインストール
- VS Code拡張機能の追加

## ライセンス

MIT License
