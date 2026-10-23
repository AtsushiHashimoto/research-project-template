#!/usr/bin/env bash
#
# 軽微な指示の受け口（段 4）。
#
#   bash scripts/flow/quick.sh start  <題>
#   bash scripts/flow/quick.sh finish --issue <N> --message <題>
#
# ★ **軽さは「コマンドの本数」で出す。検査は 1 つも落とさない。**
#   issue・worktree・`Refs #N`・PR・`/review`・品質チェックは全部そのまま通る。
#   落としたら、いま塞ごうとしている「何も通さず直接コミットする」経路と同じになる。
#
# ★ `quick.sh` が自前で持つのは**上限の検査だけ**。
#   issue の作成・枝と worktree・コミットと push・保護ブランチの判定は既存へ移譲する
#   （写経すると片方だけ直ったときに食い違う）。
#
# ★ stage は**上限の検査に使ったファイル名をそのまま**名指しで行う（git add -A を使わない）。
#
# ★ `| grep -q` / `| head ` を使わない（pipefail 下の SIGPIPE）。

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ★ 上限は**ここが唯一の定義**（環境変数で変えない）。
#   テストは定数を読まず 3 と 50 を直書きする（独立オラクル）
readonly QUICK_MAX_FILES=3
readonly QUICK_MAX_LINES=50

[ $# -ge 1 ] || die "使い方: bash scripts/flow/quick.sh <start|finish> ..."
SUB="$1"; shift

# ══════════════════════════════════════════════════════════════════
# 上限の計測
# ══════════════════════════════════════════════════════════════════
# ★ **計測では index に触らない。** `git add -N -A` で数えると、上限超過で落ちたとき
#   intent-to-add がユーザーの index に残り、`git reset` で戻すと
#   ユーザーが自分で stage したものまで剥がすため。stage は上限を通った後に行う。
measure() {  # measure <数えたパスを NUL 区切りで書くファイル> → "<ファイル数> <行数>" を出力
  local list="$1" base top add del path st u ent files=0 lines=0
  : > "$list" || die "一時ファイルに書けない"

  base="$(git merge-base "$(start_point)" HEAD)" \
    || die "共通祖先を解決できない（上限を数えられない）"

  # ── 追跡されているものの差分（未コミット分を含む）──────────────
  # ★ 3 点（`...`）は未コミット分を見ず、merge-base 無しは基点の進みが混入する（どちらも実測）
  # ★ **プロセス置換に直接渡さない**。`< <(cmd)` は cmd の終了コードを
  #   捨てるので、`git diff` が失敗すると**0 ファイル / 0 行として上限を通る**
  # ★ `--no-renames -z`: 名前の変更を「旧 => 新」の 1 行にせず、stage に使える名前で受ける
  top="$(git rev-parse --show-toplevel)" || die "リポジトリのトップレベルを解決できない"
  local numstat_file; numstat_file="$(mktemp)" || die "一時ファイルを作れない"
  git -C "$top" diff --no-renames -z --numstat "$base" > "$numstat_file" \
    || { rm -f "$numstat_file"; die "差分を取れない（上限を数えられない）"; }
  while IFS= read -r -d '' ent; do
    [ -n "$ent" ] || continue
    IFS=$'\t' read -r add del path <<< "$ent"
    # ★ バイナリは `-` で返る。数値として足すと**黙って 0 行**になる
    case "$add" in -) rm -f "$numstat_file"; die "バイナリの変更がある（$path）。行数を数えられないので quick では扱わない";; esac
    files=$((files + 1))
    lines=$((lines + add + del))
    printf '%s\0' "$path" >> "$list"
  done < "$numstat_file"
  rm -f "$numstat_file"

  # ── 追跡外のファイル（`git diff` は見ない。下で名指しで stage する）──
  # ★ **リポジトリのトップレベルから**列挙する（サブディレクトリでは足りない。実測）
  # ★ `-z` にする（空白・非 ASCII のファイル名が quotePath で化ける）
  # ★ **コマンド置換に入れない**。`$( )` は NUL を保持できないので、
  #   `-z` の出力を変数に取ると**追跡外が 1 件も数えられなくなる**（上限が丸ごと無効になる）。
  #   一時ファイルを経由すれば、NUL を保ったまま終了コードも見られる
  local others_file; others_file="$(mktemp)" || die "一時ファイルを作れない"
  git -C "$top" ls-files --others --exclude-standard -z > "$others_file" \
    || { rm -f "$others_file"; die "追跡外のファイルを列挙できない（上限を数えられない）"; }
  while IFS= read -r -d '' u; do
    files=$((files + 1))
    # ★ `grep -c ''` を使わない: バイナリを**改行バイトの数**として数え、
    #   空ファイルでは rc=1 を返して `set -euo pipefail` の下で死ぬ（どちらも実測）
    st="$(git diff --no-index --numstat /dev/null "$top/$u" 2>/dev/null || true)"
    add="${st%%	*}"
    case "$add" in
      -) die "バイナリの追跡外ファイルがある（$u）。行数を数えられないので quick では扱わない";;
      '') die "追跡外ファイルの行数を数えられない（$u）";;
    esac
    lines=$((lines + add))
    printf '%s\0' "$u" >> "$list"
  done < "$others_file"
  rm -f "$others_file"

  printf '%s %s' "$files" "$lines"
}

# ★ 子スクリプトの「次にやること」の塊を落とす。
#   `commit.sh push` と `issue-start.sh` の案内は**この流れでは誤り**で、
#   先に出るほうを読むと `/review` と `quick.sh finish` が飛ぶ。
#   「次に何をせよ」は 1 箇所で出す（lib.sh の `_next_body` の注記）。
run_child() {  # run_child <説明> <コマンド...>
  local what="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$out"; die "$what が失敗した（上の出力を見ること）"; fi
  # ★ 区切り線から先（＝次にやること）を捨て、進捗の行だけ残す
  printf '%s\n' "$out" | awk '/^════/ { skip = 1 } !skip'
}

# ══════════════════════════════════════════════════════════════════
# start
# ══════════════════════════════════════════════════════════════════
do_start() {
  local title="${1:-}" out num
  [ -n "$title" ] || die "使い方: bash scripts/flow/quick.sh start <題>"
  [ $# -le 1 ] || die "引数が多い: $*"

  head2 "軽微な指示の受け口（上限 $QUICK_MAX_FILES ファイル / $QUICK_MAX_LINES 行）"

  # ── 段 2. 既定ブランチに居ること ────────────────────────────
  local b; b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$b" ] || die "detached HEAD では実行できない"
  [[ "$b" =~ ^($PROTECTED_BRANCHES)$ ]] || next_fail \
    "いま $b に居る。quick.sh start は既定ブランチから呼ぶ。" "" \
    "  すでに issue のブランチに居るなら、そこでは commit.sh を使う:" \
    "    bash scripts/flow/commit.sh push --issue <N> --message <題>"

  # ── 段 3. 作業ツリーが綺麗であること ────────────────────────
  # ★ **変更を worktree へ移送しない**。stash / apply は失敗したとき変更が消える
  local dirty; dirty="$(git status --porcelain)" \
    || die "git status が失敗した（作業ツリーの状態を確かめられない）"
  [ -z "$dirty" ] || next_fail \
    "コミットしていない変更がある。**移送はしない**ので、先に片付けてから呼ぶこと。" "" \
    "  1. 別の issue の作業なら、その worktree でコミットする" \
    "  2. 捨ててよいなら git checkout -- . / git clean -fd" \
    "  3. 片付いてから、もう一度この行を呼ぶ"

  # ── 段 4. chore の issue を作る ─────────────────────────────
  # ★ 種類は chore だけ。選べるなら quick である必然性が無い
  out="$(bash "$REPO_ROOT/scripts/flow/issue-create.sh" --type chore --title "$title")" \
    || die "issue を作れない"
  # ★ **`作成: #<数字>` の行だけを見る**（`${out##*#}` は最後の `#` 以降を取るので、
  #   出力に他の `#` が混ざると題名などを拾う。実測）
  num="$(printf '%s\n' "$out" | sed -n 's/^作成: #\([0-9][0-9]*\)$/\1/p')"
  [[ "$num" =~ ^[0-9]+$ ]] || die "issue-create.sh の出力から番号を取れない: [$out]"

  # ── 段 5. 枝と worktree ─────────────────────────────────────
  run_child "#$num の枝 / worktree" bash "$REPO_ROOT/scripts/flow/issue-start.sh" "$num"

  # ── 段 6. 次にやること ──────────────────────────────────────
  next \
    "#$num（chore）を作った。軽微な指示として進める。" "" \
    "  1. 上の cd 先へ移って編集する" \
    "  2. bash scripts/flow/quick.sh finish --issue $num --message \"$title\"" \
    "" \
    "★ 上限は **$QUICK_MAX_FILES ファイル / $QUICK_MAX_LINES 行**（追加 + 削除の合計）。" \
    "  超えたら finish が落ちる。そのときは task として立て直すこと。"
}

# ══════════════════════════════════════════════════════════════════
# finish
# ══════════════════════════════════════════════════════════════════
do_finish() {
  local N="" MSG="" kind m files lines
  while [ $# -gt 0 ]; do
    case "$1" in
      # ★ `shift 2` は $# が 1 のとき失敗し、`set -euo pipefail` の下で**無言で終わる**
      #   commit.sh と同じく、値の不在を名指しで落とす
      --issue)   [ $# -ge 2 ] || die "--issue に値が無い"; N="$2"; shift 2;;
      --message) [ $# -ge 2 ] || die "--message に値が無い"; MSG="$2"; shift 2;;
      *) die "未知のオプション: $1";;
    esac
  done
  # ★ ブランチ名から推測しない（commit.sh の --issue 必須と揃える）
  [ -n "$N" ]   || die "--issue が無い（ブランチ名から推測しない）"
  [ -n "$MSG" ] || die "--message が無い（文言を捏造しない）"
  [[ "$N" =~ ^[0-9]+$ ]] || die "--issue の値が数値でない: '$N'"

  head2 "軽微な指示の仕上げ（#$N）"

  # ── 段 2. chore であること ──────────────────────────────────
  # ★ **open の判定はここに置かない**。`commit.sh` の
  #   `require_open_issue` が同じ文言で落とすので、ここに書いても**消しても挙動が変わらず、
  #   検査が書けない**（写経した死んだコードになる）。判定は 1 箇所に置く
  kind="$(kind_of "$(issue_labels "$N")")"
  [ "$kind" = chore ] || next_fail \
    "#$N の種類は '$kind' で chore ではない。quick は chore だけを扱う。" "" \
    "  軽微でない作業は task として回すこと:" \
    "    /task-start で task を作り、spec → feature → validation の子 issue を作る"

  # ── 段 3. 上限の検査 ────────────────────────────────────────
  local list; list="$(mktemp)" || die "一時ファイルを作れない"
  # shellcheck disable=SC2064  # $list はいま展開したい
  trap "rm -f '$list'" EXIT
  m="$(measure "$list")"; files="${m%% *}"; lines="${m##* }"
  say "  ..   変更は $files ファイル / $lines 行（上限 $QUICK_MAX_FILES / $QUICK_MAX_LINES）"
  if [ "$files" -gt "$QUICK_MAX_FILES" ] || [ "$lines" -gt "$QUICK_MAX_LINES" ]; then
    next_fail \
      "#$N: 変更が上限を超えている（$files ファイル / $lines 行。上限は $QUICK_MAX_FILES / $QUICK_MAX_LINES）。" \
      "  これは軽微な指示ではない。task として立て直すこと:" "" \
      "  1. /task-start で task を作り、spec → feature → validation の子 issue を作る" \
      "  2. **いまの変更は残っている。** この枝のまま続けてよい" \
      "  3. この issue #$N は task の子として付け替えるか、閉じること"
  fi
  say "  ok   上限の内側"

  # ── 段 4. 数えたファイルを名指しで stage し、コミットと push（既定ブランチの判定と Refs #N はそちらが行う）──
  local top; top="$(git rev-parse --show-toplevel)" || die "リポジトリのトップレベルを解決できない"
  local p
  while IFS= read -r -d '' p; do
    # ★ 消えたファイルは git add できない（既に stage 済みの削除もある）。index からだけ外す
    if [ -e "$top/$p" ] || [ -L "$top/$p" ]; then git -C "$top" add -- "$p" || die "git add -- $p が失敗した"
    else git -C "$top" rm -q --cached --ignore-unmatch -- "$p" || die "git rm --cached -- $p が失敗した"; fi
  done < "$list"
  run_child "コミット / push" \
    bash "$REPO_ROOT/scripts/flow/commit.sh" push --issue "$N" --message "$MSG"

  # ── 段 5. PR（本文には見出しだけを置く。中身は /review が書く）──
  local branch; branch="$(git symbolic-ref --quiet --short HEAD)"
  if [ -n "$(open_pr_for "$branch" "どちらを使うか決めてから呼び直すこと")" ]; then
    say "  --   PR は既にある（作り直さない）"
  else
    # ★ 本文の作り:
    #   1. `## /review 結果` は**最後に置き、下に何も書かない**。
    #      `check_pr_review` は「見出しの後の最初の非空行が `#` で始まらなければ合格」なので、
    #      「（未記入）」のような但し書きを 1 行置くだけで**合格してしまう**
    #      （＝`/review` を一度も回さずにマージまで通る。実測）
    #   2. `Closes #N` を書かない。GitHub が squash merge で issue を自動 close し、
    #      `issue-finish.sh` の完了報告コメントが**残らなくなる**
    #      （close を行うのは issue-finish.sh だけ）
    gh pr create --title "chore: $MSG (#$N)" --base "$DEFAULT_BRANCH" \
      --body "## 変更概要

$MSG

Refs #$N

## /review 結果" >/dev/null || die "gh pr create が失敗した"
    say "  ok   PR を作った（本文の '## /review 結果' は空）"
  fi

  next \
    "#$N の変更を push し、PR を用意した。" "" \
    "  1. /review を回し、PR 本文の '## /review 結果' を埋める" \
    "     ★ 空のままではマージできない（check_pr_review が見る）" \
    "  2. bash scripts/flow/issue-finish.sh $N"
}

case "$SUB" in
  start)  do_start "$@";;
  finish) do_finish "$@";;
  *) die "未知のサブコマンド: $SUB（start か finish）";;
esac
