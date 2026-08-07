---
description: issue に着手する。ブランチと worktree を作成し、仕様レビューまで進める
argument-hint: <issue番号> | --new --type <種類> --parent <task番号> --title <題>
---

# Issue Start

**issue 層の着手。** worktree を持つのは issue だけである（epic / task は持たない）。

## Usage

```
/issue-start #104                                                 # 既存 issue に着手
/issue-start --new --type feature --parent 101 --title "Xの実装"   # 新規作成して着手
```

**2つのモードを明示的に分ける。** 引数の型で暗黙に分岐させない。

| モード | 用途 |
|---|---|
| **着手** `<issue番号>` | 既存 issue のブランチと worktree を作る。`/task-run` から呼ばれるのはこちら |
| **新規** `--new ...` | `/issue-create` で作成してから着手する |

## 階層との関係

| 層 | worktree | 本スキルの対象 |
|---|---|---|
| epic | 持たない | ❌ `/task-start` の管轄 |
| task | 持たない | ❌ `/task-start` の管轄 |
| **issue** | **1つ持つ** | ✅ |
| 小タスク | 親と共有 | ❌ `/issue-branch` の管轄 |

## Workflow

### Step 1: モード判定と issue の確定

**新規モードの場合**、まず作成する。

```
Skill(skill="issue-create", args="--type ${TYPE} --title ${TITLE} --parent ${PARENT}")
```

**着手モードの場合**、issue の存在と種別を確認する。

```bash
LABELS=$(gh issue view "$ISSUE_ID" --json labels -q '[.labels[].name]|join(",")')

# epic / task には worktree を作らない
if echo "$LABELS" | grep -qE '(^|,)(epic|task)(,|$)'; then
  echo "#$ISSUE_ID は $LABELS です。epic / task は worktree を持ちません。"
  echo "task を実行する場合は /task-run を使ってください。"
  exit 1
fi
```

### Step 2: 親 task の goal を読む

```bash
PARENT=$(gh issue view "$ISSUE_ID" --json parent -q '.parent.number')
[ -n "$PARENT" ] && gh issue view "$PARENT" --json title,body
```

**親 task の「目標の状態」を読み、作業の範囲を把握する。**
**この goal は作業中に書き換えてはならない。**

親が無い issue（単発の bug 等）はそのまま進めてよい。

### Step 3: ブランチ名の決定

種類ラベルからプレフィックスを決める。

| ラベル | プレフィックス |
|---|---|
| `feature` `chore` | `feature/` |
| `spec` | `spec/` |
| `bug` | `fix/` |
| `survey` | `survey/` |
| `experiment` | `experiment/` |
| `validation` | `validation/` |
| `docs` | `docs/` |
| `refactor` | `refactor/` |

```bash
BRANCH="${PREFIX}/${ISSUE_ID}-${SLUG}"
```

### Step 4: worktree の作成

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_PATH="${REPO_ROOT}/worktrees/issue${ISSUE_ID}"

git worktree add "$WORKTREE_PATH" -b "$BRANCH"
cd "$WORKTREE_PATH"
```

**★ 注意点2つ**

1. **`worktrees/`（ドット無し）** に作る。`.gitignore` がこのパスを対象にしているため。
   ドット付きだと worktree 内の全ファイルが未追跡として `git status` を汚染する
2. **`--relative-paths` フラグは付けない。** 相対パス化の可否は
   `scripts/configure-worktree-paths.sh` が設定する `worktree.useRelativePaths` が決める
   （フラグを直接書くと git 2.48 未満で worktree 作成そのものが失敗する）。
   絶対パスで作成された場合の運用と復旧手順を含め、詳細は
   `.claude/rules/template/git-workflow.md`「Git Worktree 管理」を参照

### Step 5: 開始報告

```bash
gh issue comment "$ISSUE_ID" --body "## 着手

- ブランチ: \`${BRANCH}\`
- Worktree: \`worktrees/issue${ISSUE_ID}\`"
```

**作業中を表す状態ラベルは付けない。** 作業中の判定はブランチの有無で行う
（同じ状態を2通りに表現しないため。`.claude/rules/template/labels.md` 参照）。

### Step 6: 仕様レビュー（`/review-spec`）

`/task-run` 経由の場合はスキップする（呼び出し元の Step 1.5 で実行されるため）。

手動実行の場合はここで仕様を確認する。
不明点がありユーザーが即答できない場合は `/qa-ask` で非同期に投げて作業を続行する。

## Output

- Issue URL・番号・種別
- 親 task とその goal
- ブランチ名 / Worktree パス
- 次のステップ

## Related Skills

| スキル | 関係 |
|-------|------|
| `/issue-create` | 新規モードで作成に使用（作成の単一情報源） |
| `/task-start` | epic / task の作成はこちら |
| `/task-run` | 本スキルを各子 issue に対して呼ぶ |
| `/issue-branch` | 同一 worktree 内で小タスクを分ける場合 |
| `/issue-finish` | 完了・マージ |
