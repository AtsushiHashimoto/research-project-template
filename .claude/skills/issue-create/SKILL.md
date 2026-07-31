---
description: Issue 作成の単一情報源。epic/task/issue のいずれも作成し、親子リンクを張る
argument-hint: --type <epic|task|issue-type> --title <題> [--parent <N>]
---

# Issue Create

**Issue 作成の唯一の実装。** 他のスキルは `gh issue create` を直接呼ばず、必ず本スキルを経由する。

## なぜ一元化するか

以前は `/issue-start` `/issue-gaps` `/issue-unblock` `/issue-backlog` `/issue-cycle` が
それぞれ `gh issue create` を直書きしており、ラベル付与・Assignee・本文フォーマット・
親子リンクの扱いが統一されていなかった（単一情報源の原則に反する）。

## Usage

```
/issue-create --type epic     --title "手法Xの確立"
/issue-create --type task     --title "基礎検証"        --parent 100
/issue-create --type survey   --title "先行研究の調査"   --parent 101
/issue-create --type feature  --title "Xの実装"         --parent 101
```

| 引数 | 必須 | 説明 |
|---|---|---|
| `--type` | ✅ | `epic` / `task` / 種類ラベル（`survey` `spec` `feature` `validation` `experiment` `bug` `docs` `refactor` `chore`） |
| `--title` | ✅ | タイトル。接頭辞は付けない（種別はラベルで表す） |
| `--parent` | epic 以外は原則必須 | 親 Issue 番号。GitHub ネイティブ sub-issue でリンクする |
| `--body-file` | | 本文ファイル。省略時は type に応じた雛形 |

## Workflow

### Step 1: 前提チェック

```bash
# ラベルが存在するか（無ければプロビジョニングを促す）
if ! gh label list --limit 100 --json name -q '.[].name' | grep -qx "$TYPE"; then
  echo "ラベル '$TYPE' がありません。以下を実行してください:"
  echo "  bash scripts/setup-labels.sh"
  exit 1
fi
```

### Step 2: 親の存在と種別の妥当性を確認

**階層のルール:**

| 作るもの | 許される親 |
|---|---|
| `epic` | なし（最上位） |
| `task` | `epic` |
| issue（種類ラベル） | `task` |

```bash
if [ -n "$PARENT" ]; then
  PARENT_LABELS=$(gh issue view "$PARENT" --json labels -q '[.labels[].name]|join(",")')
  # task の親は epic、issue の親は task であることを確認
fi
```

**親の種別が想定と違う場合は警告して停止する。** 勝手に補正しない。

### Step 3: 本文の生成

`--body-file` が無い場合、type に応じた雛形を使う。

**epic の雛形:**

```markdown
## ゴール

<何が達成できたら完了か。測定可能な形で>

## 背景

<なぜこれをやるのか>

## 完了条件

- [ ] <ゴールに対応する検証可能な条件>

---
**このゴールは変更しない。** 変更が必要な場合は新しい epic を立て、
本 epic は「達成されなかった」記録として閉じる（CLAUDE.md「ゴールの不変性」参照）。
```

**task の雛形**: `/task-start` が対話で埋めるため、本スキルを直接呼ばず `/task-start` を使うこと。

**issue の雛形:**

```markdown
## 目的

<この issue で何を達成するか。親 task のどの部分か>

## 完了条件

- [ ] <検証可能な条件>

## 関係

- Parent: #<PARENT>
```

### Step 4: Issue 作成

```bash
URL=$(gh issue create \
  --title "$TITLE" \
  --body-file "$BODY_FILE" \
  --label "$TYPE" \
  --assignee @me)

# URL から番号を取得する（gh issue list に頼らない）
ISSUE_ID="${URL##*/}"
echo "作成: #$ISSUE_ID"
```

**★ 番号の取得方法に注意**

かつては以下のように取得していたが、**レースコンディションを含むため禁止**:

```bash
# ❌ 禁止: 直前に自分が作った Issue が最新とは限らない
ISSUE_ID=$(gh issue list --limit 1 --json number --jq '.[0].number')
```

`gh issue create` は作成した Issue の URL を stdout に返すので、そこから取る。

### Step 5: 親子リンクを張る

GitHub ネイティブの sub-issue を使う。**本文テキストの `Parent: #N` は補助的な表示に留め、
構造の正は API 側とする。**

```bash
if [ -n "$PARENT" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  CHILD_NODE_ID=$(gh api "repos/$REPO/issues/$ISSUE_ID" --jq '.id')

  # ★ -F（integer）で渡すこと。-f（文字列）だと 422 Invalid property になる
  gh api -X POST "repos/$REPO/issues/$PARENT/sub_issues" \
    -F sub_issue_id="$CHILD_NODE_ID" >/dev/null

  echo "親子リンク: #$PARENT → #$ISSUE_ID"
fi
```

**確認:**

```bash
gh issue view "$ISSUE_ID" --json parent -q '.parent.number'
```

### Step 6: 出力

- Issue URL と番号
- 親子リンクの結果
- 次に取るべき操作（task なら `/task-run`、issue なら `/issue-start`）

## 親子リンクの解除

```bash
gh api -X DELETE "repos/$REPO/issues/$PARENT/sub_issue" -F sub_issue_id="$CHILD_NODE_ID"
```

## 呼び出し元

| スキル | 用途 |
|-------|------|
| `/task-start` | epic / task と既定構成の子 issue を作成 |
| `/issue-start` | 新規 issue の作成（既存 issue への着手時は呼ばない） |
| `/issue-gaps` | 乖離検出で見つかった不足 issue |
| `/issue-unblock` | ブロッカー解消 issue |
| `/issue-backlog` | バックログの issue 化 |
| `/epic-cycle` | integrity 検出結果の issue 化 |

**これらのスキルで `gh issue create` を直接呼ばないこと。**

## Note

- `in-progress` ラベルは付けない。作業中の判定はブランチの有無で行う（CLAUDE.md 参照）
- ラベル定義の追加・変更は `scripts/setup-labels.sh` と CLAUDE.md の両方を更新する
