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
- `.claude/CLAUDE.md` — プロジェクト設定（汚染チェック必須）
- `.devcontainer/` — DevContainer設定
- `scripts/` — ユーティリティスクリプト
- `install.sh` — インストーラー

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
    ".claude/CLAUDE.md"
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
- `.claude/skills/review/SKILL.md` — レビュー手順改善

### ローカルで追加されたファイル
- `.claude/skills/new-skill/SKILL.md` — 新規スキル

テンプレートに貢献するファイルを選択してください。
```

### Step 3: ユーザーが貢献するファイルを選択

各変更について貢献するかどうか確認。

### Step 4: プロジェクト固有コンテンツの汚染チェック（必須）

**★★★ このステップは絶対にスキップしない ★★★**

貢献予定の各ファイルに対して、プロジェクト固有の内容が混入していないか検証する。
テンプレートに push されるファイルは汎用的でなければならない。

#### 4-1: 機械的チェック（置換ログベース）

`install.sh` が生成する `.claude/template-substitutions.json` を使い、
プロジェクト固有の値がファイルに残っていないかチェック:

```bash
SUBSTITUTIONS_FILE=".claude/template-substitutions.json"

if [ -f "$SUBSTITUTIONS_FILE" ]; then
  echo "=== 置換ログベースの汚染チェック ==="
  CONTAMINATED=false

  for key in $(jq -r 'keys[]' "$SUBSTITUTIONS_FILE"); do
    value=$(jq -r ".[\"$key\"]" "$SUBSTITUTIONS_FILE")
    # 空値やTODOプレースホルダーはスキップ
    if [ -n "$value" ] && [[ "$value" != TODO:* ]]; then
      for file in $SELECTED_FILES; do
        matches=$(grep -n "$value" "$file" 2>/dev/null || true)
        if [ -n "$matches" ]; then
          echo "CONTAMINATION in $file: $key=$value"
          echo "$matches"
          CONTAMINATED=true
        fi
      done
    fi
  done

  if [ "$CONTAMINATED" = true ]; then
    echo ""
    echo "⚠️ プロジェクト固有の値が検出されました。"
    echo "プレースホルダー（{{...}}）または汎用的な表現に置き換えてください。"
  else
    echo "✅ 機械的チェック: 汚染なし"
  fi
else
  echo "⚠️ .claude/template-substitutions.json が見つかりません。"
  echo "install.sh で生成されるファイルです。手動チェックに進みます。"
fi
```

#### 4-2: 汚染が検出された場合

1. 該当箇所をユーザーに提示
2. プレースホルダー `{{...}}` または汎用的な表現に置き換え
3. 置き換え後の内容をユーザーに確認

### Step 5: 品質レビュー（/review）

**★★★ このステップは絶対にスキップしない ★★★**

`/review` と同じサブエージェントベースのレビューを実行する。
テンプレートに push するコードもプロジェクトコードと同じ品質基準でレビューする。

```
Skill(skill="review")
```

レビューで問題が検出された場合は修正してから続行。

### Step 6: テンプレートリポジトリへのアクセス方式の決定

テンプレートリポジトリへの push 権限があるか確認:

```bash
# 直接 push できるか確認
gh repo view "$TEMPLATE_REPO" --json viewerPermission -q '.viewerPermission'
```

- **ADMIN/WRITE**: 直接ブランチを作成してPR
- **READ/NONE**: fork 経由でPR

### Step 7: ブランチ作成と変更のプッシュ

#### 直接アクセスの場合

```bash
cd "$TMP_DIR/template"

BRANCH_NAME="contribute/$(date +%Y%m%d)-improvements"
git checkout -b "$BRANCH_NAME"

# 選択されたファイルをコピー
for file in $SELECTED_FILES; do
  cp "$PROJECT_ROOT/$file" "$TMP_DIR/template/$file"
done

git add .
git commit -m "feat: contribute improvements from downstream project"
git push -u origin "$BRANCH_NAME"
```

#### fork 経由の場合

```bash
FORK_REPO=$(gh repo list --fork --json nameWithOwner --jq '.[].nameWithOwner' | grep "research-project-template")

# fork がなければ作成
if [ -z "$FORK_REPO" ]; then
  gh repo fork "$TEMPLATE_REPO" --clone=false
  FORK_REPO=$(gh repo list --fork --json nameWithOwner --jq '.[].nameWithOwner' | grep "research-project-template")
fi

git clone "https://github.com/$FORK_REPO" "$TMP_DIR/fork"
cd "$TMP_DIR/fork"

BRANCH_NAME="contribute/$(date +%Y%m%d)-improvements"
git checkout -b "$BRANCH_NAME"

for file in $SELECTED_FILES; do
  cp "$PROJECT_ROOT/$file" "$TMP_DIR/fork/$file"
done

git add .
git commit -m "feat: contribute improvements from downstream project"
git push -u origin "$BRANCH_NAME"
```

### Step 8: PR作成

```bash
gh pr create \
    --repo "$TEMPLATE_REPO" \
    --head "$BRANCH_NAME" \
    --title "feat: contribute improvements from downstream project" \
    --body "## 変更概要

[変更内容の説明]

## 変更の意図

[なぜこの変更が必要か]

## 品質チェック

- ✅ 汚染チェック実施（template-substitutions.json ベース）
- ✅ /review レビュー実施

## 影響範囲

[テンプレートを使用する他のプロジェクトへの影響]

---
*This PR was created via \`/template/contribute\` command.*"
```

### Step 9: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

## Implementation

1. テンプレートの最新版をcloneして差分を検出
2. 変更候補をユーザーに提示
3. 貢献するファイルの選択を受ける
4. **汚染チェック**: template-substitutions.json ベースの機械的チェック
5. **品質レビュー**: /review サブエージェントによるレビュー
6. アクセス方式の決定（直接 or fork）
7. ブランチ作成、選択ファイルをコピー
8. コミット＆プッシュ
9. テンプレートリポジトリにPRを作成
10. PR URLを表示

**重要**:
- 汚染チェックと品質レビューは省略禁止
- PRの説明には変更の意図と影響を必ず記載
- ユーザーの確認なしにPRを作成しない

## Note

- テンプレートからの更新取り込みは `/template/sync` を使用
- GitHub認証が必要（`gh auth status` で確認可能）
