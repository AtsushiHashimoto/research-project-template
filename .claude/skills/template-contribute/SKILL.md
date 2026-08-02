---
description: Contribute improvements back to research-project-template (テンプレートへの改善PR)
---

# Template Contribute（テンプレートへの改善PR）

テンプレート由来ファイルへのローカル改変を検出し、テンプレートリポジトリへの PR として還流します。

## 用途

- テンプレートのバグ修正をフィードバック
- 新しいスキルやエージェント定義をテンプレートに追加提案
- スクリプト・ワークフロールールの改善をテンプレートに還元

## ★ 判別基準

**テンプレート由来パスの変更＝還流候補。それ以外＝プロジェクト固有（還流しない）。**

還流が 2026-04-08 以降 0 件だった原因の1つは「何を還流すべきかの基準が無い」ことでした。
基準はパスで機械的に決めます。

| 還流候補（テンプレート由来） | 対象外（プロジェクト固有） |
|---|---|
| `.claude/rules/template/`（`MANIFEST.sha256` は生成物なので除外） | `.claude/rules/` 直下（ローカルルール） |
| `.claude/skills/` | `.claude/CLAUDE.md`（固有の概要・制約を含む） |
| `.claude/agents/` | `.spec/` の**プロジェクト固有節**（`# プロジェクト固有` 以降） |
| `scripts/` | `.spec/issues/`, `.spec/decisions/`, `.spec/subsystems/` |
| `.spec/*.md` の**既定節**（`# 既定の` 〜 `# プロジェクト固有` の直前） | `data/`, `docs/`, `.dev/`, その他すべて |
| `.claude/rules/template.bak-*/`（下記） | `.claude/template-source.json`（fork 先の URL） |
| | `.gitignore`（プロジェクト固有の追記が混ざる。テンプレートへ反映したい場合は `scripts/ensure-gitignore.sh` の一覧を編集して還流する） |

**`.claude/rules/template.bak-*/` も検出対象に含めます。** `/template-sync` が
ローカル改変を検出して退避したディレクトリであり、そこにあるファイルは
「テンプレート由来ファイルへのローカル改変＝還流候補そのもの」だからです
（退避元のパスは `template.bak-<日時>/` を除いた相対パスに対応します）。

判別と diff 生成の実体は **`scripts/template-contribute-detect.sh`** です。
このリストを SKILL.md 側に書き写して二重管理しないこと（単一情報源）。

## Workflow

### Step 1: テンプレートの最新版を clone

**取得に失敗したら、そこで中止する。** 部分適用も無言終了もしない。

**URL をここに書かないこと。** テンプレートの所在は `.claude/template-source.json` が正で、
読み取りは `scripts/template-source.sh` が単一情報源（#122 D3）。
同ファイルが無い既存プロジェクトではハードコードの既定値に落ちるが、その旨が stderr に出る。

```bash
TEMPLATE_REPO=$(bash scripts/template-source.sh)        # 既定値に落ちた場合は警告が出る
TEMPLATE_NAME=$(bash scripts/template-source.sh --name) # fork 検出の grep に使う
PROJECT_ROOT=$(git rev-parse --show-toplevel)
TMP_DIR=$(mktemp -d)
if ! git clone --depth 1 "$TEMPLATE_REPO" "$TMP_DIR/template"; then
    echo "ERROR: テンプレートの取得に失敗しました（ネットワーク / URL を確認）。" >&2
    rm -rf "$TMP_DIR"
    exit 1
fi
```

### Step 2: 還流候補の検出（スクリプトに委譲）

```bash
bash scripts/template-contribute-detect.sh --source "$TMP_DIR/template"
```

出力例:

```
=== 還流候補の検出 ===
還流候補 3 件（テンプレート由来パスの変更）:
  [変更] .claude/rules/template/labels.md
  [追加] .claude/skills/my-new-skill/SKILL.md
  [変更] .claude/rules/template.bak-20260731-101112/template/doc-principles.md
```

- `[変更]` … テンプレートにも存在するが内容が違う
- `[追加]` … ローカルにのみ存在する（新規スキル等）

候補が 0 件なら**ここで終了**する（PR は作らない）。

### Step 3: 変更ファイル一覧の提示と選択

各候補の unified diff を表示し、還流するかをユーザーに確認します。

```bash
# 機械可読な一覧（1行1パス）
bash scripts/template-contribute-detect.sh --source "$TMP_DIR/template" --format paths

# 個別の diff
bash scripts/template-contribute-detect.sh --source "$TMP_DIR/template" \
    --diff ".claude/rules/template/labels.md"
```

提示のしかた:

```markdown
## 還流候補（3件）

### 1. `.claude/rules/template/labels.md` [変更]
```diff
（--diff の出力）
```
→ 還流しますか？（汎用的な改善か、このプロジェクト固有かで判断）
```

- **ユーザーの選択なしに勝手に PR を作らない**
- 選択されたパスを `SELECTED_FILES` に集める
- `.spec/*.md (既定節)` が選ばれた場合、還流するのは**既定節だけ**である点を明示する
  （固有節はコピーしない）
- `template.bak-*/` 配下が選ばれた場合、テンプレート側の反映先は
  `.claude/rules/template/<相対パス>` になる

### Step 4: プロジェクト固有コンテンツの汚染チェック（必須）

**★★★ このステップは絶対にスキップしない ★★★**

テンプレートに push されるファイルは汎用的でなければならない。

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

汚染が検出された場合は、該当箇所をユーザーに提示し、プレースホルダーまたは
汎用的な表現に置き換えてから続行する。

### Step 5: 品質レビュー（/review）

**★★★ このステップは絶対にスキップしない ★★★**

テンプレートに push するコードもプロジェクトコードと同じ品質基準でレビューする。

```
Skill(skill="review")
```

レビューで問題が検出された場合は修正してから続行。

### Step 6: アクセス方式の決定

```bash
gh repo view "$TEMPLATE_REPO" --json viewerPermission -q '.viewerPermission'
```

- **ADMIN/WRITE**: テンプレートに直接 contribute ブランチを作成
- **READ/NONE**: fork してから contribute ブランチを作成

```bash
if [ "$PERM" = "ADMIN" ] || [ "$PERM" = "WRITE" ]; then
  WORK_REPO="$TMP_DIR/template"
else
  # 検索語はリポジトリ名から導出する（fork 名をハードコードしない。#122 D3）
  FORK_REPO=$(gh repo list --fork --json nameWithOwner --jq '.[].nameWithOwner' \
              | grep -F "$TEMPLATE_NAME")
  if [ -z "$FORK_REPO" ]; then
    gh repo fork "$TEMPLATE_REPO" --clone=false
    FORK_REPO=$(gh repo list --fork --json nameWithOwner --jq '.[].nameWithOwner' \
                | grep -F "$TEMPLATE_NAME")
  fi
  git clone "https://github.com/$FORK_REPO" "$TMP_DIR/fork"
  WORK_REPO="$TMP_DIR/fork"
fi
```

### Step 7: contribute ブランチの作成と反映

```bash
cd "$WORK_REPO"
BRANCH_NAME="contribute/$(date +%Y%m%d)-${TOPIC:-improvements}"
git checkout -b "$BRANCH_NAME"
```

選択されたファイルを反映します。**パスの種類ごとに反映先が違う**ことに注意:

| 候補のパス | テンプレート側の反映先 | 反映方法 |
|---|---|---|
| `.claude/rules/template/...`, `.claude/skills/...`, `.claude/agents/...`, `scripts/...` | 同じパス | ファイルごとコピー |
| `.claude/rules/template.bak-<日時>/template/<rel>` | `.claude/rules/template/<rel>` | ファイルごとコピー |
| `.spec/<name>.md (既定節)` | `.spec/<name>.md` の既定節 | **既定節だけを差し替える**（固有節はコピーしない） |

```bash
# 例: 通常ファイル
cp "$PROJECT_ROOT/.claude/rules/template/labels.md" \
   "$WORK_REPO/.claude/rules/template/labels.md"

# .claude/rules/template/ を変更した場合は MANIFEST を再生成する（quality-check が検査する）
bash "$WORK_REPO/scripts/generate-rules-manifest.sh" "$WORK_REPO/.claude/rules/template"
```

`.spec/` の既定節を還流する場合は、テンプレート側で既定節だけを差し替える
（`scripts/spec-defaults-common.sh` の `spec_bounds` が示す範囲）。
固有節（`# プロジェクト固有` 以降）は**絶対にコピーしない**。

### Step 8: PR 本文の自動生成と PR 作成

**PR 本文には次の3項目を必ず含める。** 還流が続かなかった原因の1つは
「なぜテンプレートに入れるべきかが説明されず、レビューが止まる」ことでした。

| 項目 | 内容 | 取得元 |
|---|---|---|
| **元 issue** | この改変が生まれた下流プロジェクトの issue | ブランチ名の issue 番号 / `gh issue view` |
| **動機** | どんな失敗・不便があって直したのか | issue 本文・コミットメッセージ |
| **汎用性の根拠** | なぜ他プロジェクトにも当てはまるのか | ユーザーに確認（推測で埋めない） |

```bash
# 元 issue の特定（現在のブランチ名から）
SRC_BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current)
SRC_ISSUE=$(echo "$SRC_BRANCH" | grep -oE '[0-9]+' | head -1)
SRC_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
SRC_TITLE=$(gh issue view "$SRC_ISSUE" --json title -q '.title' 2>/dev/null || echo "")
```

```bash
git add -A
git commit -m "feat: contribute improvements from downstream project"
git push -u origin "$BRANCH_NAME"

gh pr create \
    --repo "$TEMPLATE_REPO" \
    --head "$BRANCH_NAME" \
    --title "feat: <改善の要約>" \
    --body "## 元 issue

- ${SRC_REPO}#${SRC_ISSUE} ${SRC_TITLE}

## 動機

[どんな失敗・不便があってこの改変に至ったか。実測値や再現手順があれば書く]

## 汎用性の根拠

[なぜ他プロジェクトにも当てはまるのか。プロジェクト固有の事情に依存していない理由]

## 変更ファイル

$(printf -- '- \`%s\`\n' $SELECTED_FILES)

## 品質チェック

- ✅ 汚染チェック実施（template-substitutions.json ベース）
- ✅ /review レビュー実施
- ✅ rules を変更した場合は MANIFEST.sha256 を再生成

---
*This PR was created via \`/template-contribute\`.*"
```

**「汎用性の根拠」が書けない変更は還流しない。** それはプロジェクト固有の改変です。

### Step 9: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

還流が済んだ `.claude/rules/template.bak-*/` は、PR がマージされてから削除する
（`.gitignore` 対象なのでコミットには含まれない）。

## Implementation

1. テンプレートの最新版を clone（失敗したら中止。非0 exit）
2. `scripts/template-contribute-detect.sh` で還流候補を検出（`template.bak-*/` を含む）
3. 変更ファイル一覧と unified diff を提示し、還流するファイルをユーザーが選択
4. **汚染チェック**: template-substitutions.json ベースの機械的チェック
5. **品質レビュー**: `/review` サブエージェントによるレビュー
6. アクセス方式の決定（直接 or fork）
7. contribute ブランチを作成し、選択ファイルを反映（`.spec` は既定節のみ）
8. PR 本文（元 issue・動機・汎用性の根拠）を生成して PR 作成
9. 一時ディレクトリを削除、PR URL を表示

**重要**:
- 汚染チェックと品質レビューは省略禁止
- PR 本文の3項目（元 issue・動機・汎用性の根拠）は省略禁止
- ユーザーの確認なしに PR を作成しない
- `.spec/` の固有節と `.claude/CLAUDE.md` は還流しない

## Note

- テンプレートからの更新取り込みは `/template-sync` を使用
- `/issue-finish` は完了報告に還流候補を1行提示する（契機の組み込み）
- GitHub 認証が必要（`gh auth status` で確認可能）
