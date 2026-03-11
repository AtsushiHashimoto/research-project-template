# Research Project Template

Claude Code を活用した研究プロジェクト用テンプレートです。

## 特徴

- **Issue駆動開発**: GitHub Issueを中心としたワークフロー
- **Git Worktree管理**: 並行タスクを独立したディレクトリで管理
- **データ保護**: 重要データとWorktreeの分離
- **Claude Code統合**: カスタムスキルによる自動化

---

## 既存プロジェクトへの導入

既存のプロジェクトにこのテンプレートのスキルを追加するには：

```bash
# プロジェクトディレクトリ内で実行（Gitルートを自動検出）
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash

# または、パスを明示的に指定
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- /path/to/project

# 既存ファイルを上書きする場合
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- --force
```

インストール後、`.claude/CLAUDE.md` を編集してプロジェクト固有の情報を設定してください。

---

## 新規プロジェクトのセットアップ

### 1. テンプレートからリポジトリを作成

```bash
git clone https://github.com/AtsushiHashimoto/research-project-template.git my-project
cd my-project
chmod +x setup.sh
./setup.sh "My Project Name" "Project description" "Your Name"
```

### 2. GitHubリポジトリを作成

```bash
# 個人アカウントの場合
gh repo create my-project --public

# Organizationの場合
gh repo create YOUR_ORG/my-project --public

git push -u origin main
```

### 3. 開発環境を起動

VS Code で Dev Container を使用する場合:
1. VS Code でプロジェクトを開く
2. "Reopen in Container" を選択
3. Claude Code を起動: `claude`

---

## ディレクトリ構成

```
my-project/
├── .claude/
│   ├── CLAUDE.md              # プロジェクト設定・ワークフロー定義
│   ├── commands/              # カスタムスキル（コマンド）
│   └── skills/                # 追加スキル
├── scripts/                   # スタンドアロンスクリプト
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
├── data/
│   └── shared/                # 共有データ（Worktree間で共有）
│       └── ollama_models/     # Ollamaモデル（オプション）
└── worktrees/                 # Worktree用ディレクトリ（.gitignore対象）
```

---

## クイックスタート

```bash
# 1. タスクを開始
/issue/start データセットの前処理を実装

# 2. 作業して途中保存
/commit/push

# 3. タスクを完了
/issue/finish
```

---

## カスタムスキル一覧

| スキル | 用途 |
|-------|------|
| `/issue/start [説明]` | 新しいタスクを開始（Issue + Branch + Worktree） |
| `/issue/branch [説明]` | 現在のWorktree内で子タスクを作成 |
| `/issue/report` | 進捗をIssueに報告 |
| `/issue/finish` | タスクを完了（レビュー + マージ + クリーンアップ） |
| `/commit` | ローカルにコミット |
| `/commit/push` | コミット＆プッシュ（途中保存） |
| `/commit/merge` | コミット＆マージ（タスク完了） |
| `/review` | 多角的コードレビュー |
| `/template/sync` | テンプレートの最新更新を取り込み |
| `/template/contribute` | テンプレートへの改善PRを作成 |

---

## カスタマイズ

以下をカスタマイズできます：

- **`.claude/CLAUDE.md`**: プロジェクト固有のルールとワークフロー
- **`.devcontainer/Dockerfile`**: ベースイメージ、パッケージ、ツール（Ollamaなど）
- **`.devcontainer/devcontainer.json`**: VS Code拡張機能、環境変数

詳細なカスタマイズ手順は `.claude/CLAUDE.md` を参照してください。

---

## ライセンス

MIT License
