#!/usr/bin/env bash
#
# Issue 作成の唯一の実装。**`gh issue create` を直に呼ぶのはこのファイルだけ**。
#
#   bash scripts/flow/issue-create.sh --type <T> --title <題> [--parent <P>]
#                                     [--body-file <F>] [--extra-label <L>]...
#
# ★ **stdout には `作成: #<N>` の 1 行だけを出す**（機械が読む）。
#   人間向けの出力は stderr。issue-branch.sh がこの行から子番号を取る。

# shellcheck source=scripts/flow/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ★ 以後の出力は stderr。fd 3 が本来の stdout（機械向け 1 行だけ流す）
exec 3>&1 1>&2

TYPE=""; TITLE=""; PARENT=""; BODY_FILE=""
declare -a EXTRA=()

# ── 段 1. 引数（★ 未知のオプションで落ちる。打ち間違いで黙ってラベル無しにしない）──
while [ $# -gt 0 ]; do
  case "$1" in
    --type)        [ $# -ge 2 ] || die "--type に値が無い";        TYPE="$2"; shift 2;;
    --title)       [ $# -ge 2 ] || die "--title に値が無い";       TITLE="$2"; shift 2;;
    --parent)      [ $# -ge 2 ] || die "--parent に値が無い";      PARENT="$2"; shift 2;;
    --body-file)   [ $# -ge 2 ] || die "--body-file に値が無い";   BODY_FILE="$2"; shift 2;;
    --extra-label) [ $# -ge 2 ] || die "--extra-label に値が無い"; EXTRA+=("$2"); shift 2;;
    *) die "未知の引数: $1
使い方: bash scripts/flow/issue-create.sh --type <T> --title <題> [--parent <P>]
        [--body-file <F>] [--extra-label <L>]...";;
  esac
done
[ -n "$TYPE" ]  || die "--type が無い"
[ -n "$TITLE" ] || die "--title が無い"

head2 "issue を作る（--type $TYPE${PARENT:+ / --parent #$PARENT}）"

# ── 段 2. ラベルの存在確認 ──────────────────────────────────────
# ★ `--limit 200` を必ず付ける。既定は 30 件で、実測のラベルは 29 件しかない
#   （ラベルが 30 個を超えると有効な --type が「存在しない」と判定されて恒偽になる）
labels_defined="$(gh_json "ラベル一覧の取得" gh label list --limit 200 --json name -q '[.[].name]|join(",")')"
for l in "$TYPE" "${EXTRA[@]+"${EXTRA[@]}"}"; do
  has_label "$labels_defined" "$l" \
    || die "ラベル '$l' が存在しない。bash scripts/setup-labels.sh を実行すること"
done
say "  ok   ラベル $TYPE${EXTRA[0]+ + ${EXTRA[*]}} は定義済み"

# ── 段 3. 階層の照合（issue-hierarchy.md。当てはまらない親子は非ゼロ終了）────
# type の区分
case "$TYPE" in
  epic)             tc=epic;;
  task)             tc=task;;
  review-integrity) tc=report;;
  *) [ -n "$(kind_of "$TYPE")" ] && tc=kind || tc=other;;
esac

# 親の区分（無ければ none）
class_of_issue() {
  local n="$1" l
  l="$(issue_labels "$n")"
  if   has_label "$l" epic; then printf 'epic'
  elif has_label "$l" task; then printf 'task'
  elif [ -n "$(kind_of "$l")" ]; then printf 'kind'
  elif has_label "$l" review-integrity; then printf 'report'
  else printf 'other'; fi
}

pc=none
if [ -n "$PARENT" ]; then
  pc="$(class_of_issue "$PARENT")"
  say "  ..   親 #$PARENT の区分: $pc"
fi

case "$tc/$pc" in
  epic/none) say "  ok   epic（最上位）";;
  epic/epic)
    # ★ 入れ子は 2 段まで（epic → sub-epic → task）。3 段目は止める
    gp="$(issue_parent "$PARENT")"
    if [ -n "$gp" ] && [ "$(class_of_issue "$gp")" = epic ]; then
      die "epic の入れ子が 3 段目になる（#$gp → #$PARENT → 新規）。
goal の切り方を疑うこと（.claude/rules/template/issue-hierarchy.md の sub-epic）"
    fi
    say "  ok   sub-epic（2 段目）";;
  task/epic) say "  ok   task の親は epic";;
  kind/task) say "  ok   issue の親は task";;
  kind/kind) say "  ok   小タスク（親は issue 層）";;
  kind/none) say "  ok   親なしの単独 issue（★ 下で明示する）";;
  report/none) say "  ok   報告 issue（単独）";;
  *) die "階層のルールに当てはまらない親子関係: --type $TYPE（区分 $tc）の親が $pc。
勝手に補正しない。.claude/rules/template/issue-hierarchy.md の階層表を確認すること
（許される組み合わせ: epic/なし・epic/epic・task/epic・種類/task・種類/種類・種類/なし・報告/なし）";;
esac

# ── 段 4. 本文（--body-file が無ければ type 別の雛形）──────────────
TMP_BODY=""
if [ -z "$BODY_FILE" ]; then
  TMP_BODY="$(mktemp)"
  # shellcheck disable=SC2064  # $TMP_BODY はいま展開したい
  trap "rm -f '$TMP_BODY'" EXIT
  case "$tc" in
    epic) cat >"$TMP_BODY" <<'EOF'
## ゴール

<何が達成できたら完了か。測定可能な形で>

## 背景

<なぜこれをやるのか>

## 前提（ユーザー確定事項）

<この epic だけに効く前提・範囲・禁止事項。プロジェクト大前提は `.spec/invariants.md` の P-xx を参照で書く。
推測で埋めない（`.claude/rules/template/premises.md`）>

## 完了条件

- [ ] <ゴールに対応する検証可能な条件>

---
**このゴールは変更しない。** 変更が必要な場合は新しい epic を立て、
本 epic は「達成されなかった」記録として閉じる（`.claude/rules/template/issue-hierarchy.md`「ゴールの不変性」）。
EOF
;;
    task) die "task の本文は /task-start が対話で埋める。--body-file 無しで task を作らないこと";;
    *) cat >"$TMP_BODY" <<'EOF'
## 目的

<この issue で何を達成するか。親 task のどの部分か>

## 完了条件

- [ ] <検証可能な条件>
EOF
;;
  esac
  BODY_FILE="$TMP_BODY"
fi
[ -s "$BODY_FILE" ] || die "本文ファイルが空: $BODY_FILE"

# ── 段 5. 作成（★ 番号は URL から取る。gh issue list を使わない）────
declare -a ARGS=(--title "$TITLE" --body-file "$BODY_FILE" --label "$TYPE" --assignee @me)
for l in "${EXTRA[@]+"${EXTRA[@]}"}"; do ARGS+=(--label "$l"); done

# ★ gh_json を通さない（gh が stderr に出す通知と分けて URL だけを受ける）。
#   rc は明示的に見る
URL="$(gh issue create "${ARGS[@]}")" || die "gh issue create が失敗した"
NUM="${URL##*/}"
[[ "$NUM" =~ ^[0-9]+$ ]] || die "作成した issue の番号を URL から取れない: $URL"
say "  ok   作成: #$NUM（$URL）"

# ── 段 7'(先出し). 番号を機械向けに出す ────────────────────────────
# ★ 段 6 が失敗しても番号は出す。出さずに落ちると、再実行で**重複起票**する
printf '作成: #%s\n' "$NUM" >&3

# ── 段 6. 親子リンク（GitHub ネイティブ sub-issue）────────────────
if [ -n "$PARENT" ]; then
  repo="$(gh_repo)"
  # ★ issue 番号ではなく**内部 id**を渡す（番号だと 422）。`-f` ではなく `-F`
  child_id="$(gh_json "#$NUM の内部 id 取得" gh api "repos/$repo/issues/$NUM" --jq '.id')"
  gh_json "#$PARENT → #$NUM のリンク" \
    gh api -X POST "repos/$repo/issues/$PARENT/sub_issues" -F sub_issue_id="$child_id" >/dev/null
  say "  ok   親子リンク: #$PARENT → #$NUM"
else
  say "  ★    親を指定せずに**単独 issue**として作成した（#$NUM）"
fi

say ""
say "次: issue なら bash scripts/flow/issue-start.sh $NUM / task なら /task-run $NUM"
