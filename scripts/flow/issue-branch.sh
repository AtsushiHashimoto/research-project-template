#!/usr/bin/env bash
#
# いまの worktree の中で小タスク（子 issue）を作る。**ブランチも worktree も切り替えない**。
#
#   bash scripts/flow/issue-branch.sh --title <題> [--type <T>]
#
# 親はブランチ名の番号（task 単位のブランチなら task、単独 issue ならその issue）。
#
# ★ これが /issue-start との違い: 作成が本体なので、内部で issue-create.sh を呼ぶ。

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TITLE=""; TYPE="feature"   # 既定は feature（ここが単一情報源）

while [ $# -gt 0 ]; do
  case "$1" in
    --title) [ $# -ge 2 ] || die "--title に値が無い"; TITLE="$2"; shift 2;;
    --type)  [ $# -ge 2 ] || die "--type に値が無い";  TYPE="$2";  shift 2;;
    *) die "未知の引数: $1
使い方: bash scripts/flow/issue-branch.sh --title <題> [--type <T>]";;
  esac
done
[ -n "$TITLE" ] || die "--title が無い"

# ── 段 1. 現在のブランチから親番号を取る ─────────────────────────
# ★ `grep -oE '[0-9]+' | head -1` を使わない（pipefail の禁止形）。
#   さらに「最初の数字」ではなく **<type>/ の直後**で取る
#   （ブランチ名に i12 のような追加の数字が入るため。spec/10-i12 → 10）
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || die "detached HEAD では実行できない"
# ★ `case` のパターンに変数を置くと `|` が選択肢にならない（展開後に構文解釈されない）。
#   `[[ =~ ]]` なら正規表現の一部として効く
[[ ! "$BRANCH" =~ ^($PROTECTED_BRANCHES)$ ]] \
  || die "ブランチ: $BRANCH に居る。issue のブランチで実行すること"
[[ "$BRANCH" =~ ^($BRANCH_TYPES)/([0-9]+)- ]] \
  || die "ブランチ '$BRANCH' が <type>/<番号>-* の形でない。親 issue の番号を取れない"
PARENT="${BASH_REMATCH[2]}"

head2 "小タスクを作る（親 #$PARENT / --type $TYPE）"

# ── 段 2. 本文 ──────────────────────────────────────────────────
BODY="$(mktemp)"
# shellcheck disable=SC2064  # $BODY はいま展開したい
trap "rm -f '$BODY'" EXIT
cat >"$BODY" <<EOF
## 目的

$TITLE

## 作業場所

- ブランチ: \`$BRANCH\`（**親 #$PARENT と同じ worktree**。切り替えない）
- コミット時の参照: \`Refs #<この issue の番号>\`

## 完了条件

- [ ] <検証可能な条件>
EOF

# ── 段 3. issue-create.sh を呼ぶ（★ gh issue create は直に呼ばない）──
# ★ stdout は `作成: #<N>` の 1 行だけ。ここを解析する
out="$(bash "$REPO_ROOT/scripts/flow/issue-create.sh" \
        --type "$TYPE" --title "$TITLE" --parent "$PARENT" --body-file "$BODY")" \
  || die "issue-create.sh が失敗した。捕獲した stdout: '${out:-（空）}'
★ '作成: #N' が入っているなら **issue は作成済み**で、親子リンクだけが失敗している。
  作り直さないこと（重複起票になる）"
[[ "$out" =~ 作成:[[:space:]]*\#([0-9]+) ]] \
  || die "issue-create.sh の出力から子番号を取れない: $out"
CHILD="${BASH_REMATCH[1]}"
say "  ok   子 issue: #$CHILD"

# ── 段 4. 親と子にコメント ───────────────────────────────────────
gh issue comment "$PARENT" --body "## 小タスク作成

子 issue #$CHILD を作成しました（同一 worktree・ブランチ \`$BRANCH\`）。

- タイトル: $TITLE" >/dev/null || die "親 #$PARENT へのコメントが失敗した"

gh issue comment "$CHILD" --body "## 着手

親 #$PARENT と同じ worktree で作業します。

- ブランチ: \`$BRANCH\`
- コミット時の参照: \`Refs #$CHILD\`" >/dev/null || die "子 #$CHILD へのコメントが失敗した"

say "  ok   親 #$PARENT と子 #$CHILD にコメントした"

# ── 段 5. 次にやること ───────────────────────────────────────────
next \
  "小タスク #$CHILD を作った。**ブランチも worktree も切り替えていない**。" \
  "" \
  "  1. このまま $BRANCH で作業する" \
  "  2. コミットは Refs #$CHILD を付ける（親にも関係するなら Refs #$PARENT, #$CHILD）" \
  "  3. 小タスクは親と一緒にマージする（個別に PR を作らない）"
