---
description: Contribute improvements back to research-project-template (テンプレートへの改善PR)
---

# Template Contribute（テンプレートへの改善PR）

ローカルプロジェクトでのテンプレート関連ファイルの改善を、テンプレートリポジトリにPRとして提出します。

## 用途

- テンプレートのバグ修正をフィードバック
- 新しいスキルやコマンドをテンプレートに追加提案
- スクリプトの改善をテンプレートに還元

## 対象ファイル

テンプレート由来のファイルのみが対象です：

- `.claude/commands/` — コマンド定義
- `.claude/skills/` — スキル定義
- `.devcontainer/` — DevContainer設定
- `scripts/` — ユーティリティスクリプト
- `install.sh` — インストーラー

**対象外**: `.claude/CLAUDE.md`（プロジェクト固有のため）

## Workflow

### Step 1: テンプレート関連ファイルの変更を検出

```bash
TEMPLATE_REPO="https://github.com/AtsushiHashimoto/research-project-template"
TMP_DIR=$(mktemp -d)
git clone --depth 1 "$TEMPLATE_REPO" "$TMP_DIR/template" 2>/dev/null
```

テンプレートとローカルの差分を検出：

```bash
CONTRIBUTE_TARGETS=(
    ".claude/commands"
    ".claude/skills"
    ".devcontainer"
    "scripts"
    "install.sh"
)

for target in "${CONTRIBUTE_TARGETS[@]}"; do
    diff -rq "$TMP_DIR/template/$target" "$target" 2>/dev/null
done
```

### Step 2: 変更内容の提示

ユーザーに検出された変更を提示：

```markdown
## テンプレートへの貢献候補

### ローカルで変更されたファイル
- `scripts/safe-remove-worktree.sh` — cd ガード追加
- `.claude/commands/commit-merge.md` — Worktree削除手順改善

### ローカルで追加されたファイル
- `.claude/commands/review.md` — 新規コマンド

テンプレートに貢献するファイルを選択してください。
```

### Step 3: ユーザーが貢献するファイルを選択

各変更について貢献するかどうか確認。

### Step 4: テンプレートリポジトリのfork確認

```bash
# forkが存在するか確認
gh repo view "$TEMPLATE_REPO" --json isFork 2>/dev/null

# forkがなければ作成
gh repo fork "$TEMPLATE_REPO" --clone=false
```

### Step 5: forkにブランチを作成し変更をプッシュ

```bash
FORK_REPO=$(gh repo list --fork --json nameWithOwner --jq '.[].nameWithOwner' | grep "research-project-template")

# forkをclone（tmpディレクトリ内）
git clone "https://github.com/$FORK_REPO" "$TMP_DIR/fork"
cd "$TMP_DIR/fork"

# ブランチ作成
BRANCH_NAME="contribute/$(date +%Y%m%d)-improvements"
git checkout -b "$BRANCH_NAME"

# 選択されたファイルをコピー
# （ユーザーが選択した各ファイルについて）
cp "$PROJECT_ROOT/<file>" "$TMP_DIR/fork/<file>"

git add .
git commit -m "feat: contribute improvements from downstream project"
git push -u origin "$BRANCH_NAME"
```

### Step 6: PR作成

```bash
gh pr create \
    --repo "$TEMPLATE_REPO" \
    --head "$FORK_OWNER:$BRANCH_NAME" \
    --title "feat: contribute improvements from downstream project" \
    --body "## 変更概要

[変更内容の説明]

## 変更の意図

[なぜこの変更が必要か]

## 影響範囲

[テンプレートを使用する他のプロジェクトへの影響]

---
*This PR was created via \`/template/contribute\` command.*"
```

### Step 7: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

## Implementation

1. テンプレートの最新版をcloneして差分を検出
2. 変更候補をユーザーに提示
3. 貢献するファイルの選択を受ける
4. テンプレートリポジトリをfork（未fork時）
5. forkにブランチを作成、選択ファイルをコピー
6. コミット＆プッシュ
7. テンプレートリポジトリにPRを作成
8. PR URLを表示

**重要**:
- PRの説明には変更の意図と影響を必ず記載
- ユーザーの確認なしにPRを作成しない
- fork操作もユーザーに確認してから実行

## Note

- テンプレートからの更新取り込みは `/template/sync` を使用
- GitHub認証が必要（`gh auth status` で確認可能）
- forkの権限がない場合はエラーメッセージを表示
