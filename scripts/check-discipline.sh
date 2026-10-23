#!/usr/bin/env bash
#
# 規律の述語を 1 箇所に置く。スキルはここを呼ぶだけにする。
#
#   check-discipline.sh issue     <N> <kind> [TASK]  いまの段
#   check-discipline.sh artifacts <N> <kind>         closed の先行段（成果物だけ）
#   check-discipline.sh merge     <N> <kind> [TASK]  マージ直前（PR 本文の ## 仕様整合 を含む）
#   check-discipline.sh goal      <TASK>             goal の空欄・判定・未確定の担当と再照合
#   check-discipline.sh verdict-task <TASK>          task を閉じる前の判定コメントの形
#   check-discipline.sh merged    <N>                #N の作業が既に main に入っているか
#   check-discipline.sh epic      <EPIC>             issue に紐づかないコミットを数える
#   check-discipline.sh verdict   <EPIC>             達成判定コメントと完了条件の照合（全部 negative の確認を含む）
#
# 終了コード: 0 全て PASS / 1 いずれか FAIL / 2 使い方の誤り
#
# ★ **`| grep -q` / `| head` を使わない**（pipefail 下で生産者が SIGPIPE で死に、
#   「ヒットしたのに偽」になる）。bash の [[ =~ ]] を使う。

set -uo pipefail

FAILED=0
RAN_ANY=0

info() { printf '>>> %s\n' "$*"; }
pass() { RAN_ANY=1; printf '  ok   %s\n' "$*"; }
fail() { RAN_ANY=1; FAILED=1; printf '!!! FAILED: %s\n' "$*"; }

# ★ 行番号を固定しない（ヘッダを 1 行増やすたびに末尾が切れる）。
#   3 行目から、最初の非コメント行の直前までを出す
usage() {
  awk 'NR>2 && /^#/ {sub(/^# ?/,""); print; next} NR>2 {exit}' "${BASH_SOURCE[0]}"
  exit 2
}

# ── 語境界つきの #N 照合 ─────────────────────────────────────
# 部分文字列一致にすると日付（2026-09-16 の「16」）や桁違い（#120 が #12）に当たる。
# ★ サブプロセスを使わない（pipefail の禁止形を避ける）
refs_n() { [[ "$1" =~ (^|[^0-9])\#$2([^0-9]|$) ]]; }

file_refs_n() {
  local body
  body="$(cat "$1" 2>/dev/null)" || return 1
  refs_n "$body" "$2"
}

nonempty() { [ -s "$1" ]; }

# ── base ref の解決（既定ブランチは main 固定。git-workflow.md）────
resolve_base() {
  local cand
  for cand in origin/main main; do
    if git rev-parse --verify --quiet "$cand" >/dev/null; then
      printf '%s' "$cand"; return 0
    fi
  done
  return 1
}

# 述語の定義は別ファイル（1 ファイル 300 行の上限）
. "$(dirname "${BASH_SOURCE[0]}")/check-discipline-predicates.sh"

# ══════════════════════════════════════════════════════════════════
# モード
# ══════════════════════════════════════════════════════════════════

# ★ 仕様ファイルは **spec 段の issue 番号**で作られるので、
#   feature/validation/experiment の番号で引くと**構造上必ず落ちる**（恒偽）。
mode_artifacts() {
  local n="$1" kind="${2:-}"
  [ -n "$kind" ] || { fail "artifacts: 段の種類が指定されていない"; return; }
  info "成果物の検査 (#$n [$kind])"
  case "$kind" in
    survey)     check_survey_file "$n";;
    spec)       check_spec_file "$n"; check_auto_decisions "$n";;
    experiment) check_experiment_set "$n"; check_merged_commit "$n";;
    feature|validation|bug|docs|refactor|chore) check_merged_commit "$n";;
    *)          fail "artifacts: 未知の段の種類 '$kind'";;
  esac
}

mode_issue() {
  local n="$1" kind="${2:-}" branch_n="${3:-}"
  [ -n "$branch_n" ] || branch_n="$n"
  [ -n "$kind" ] || { fail "issue: 段の種類が指定されていない"; return; }
  info "いまの段の検査 (#$n [$kind]。ブランチは #$branch_n で見る)"
  check_branch "$branch_n"
  check_worktree_diff
  # ★ **feature / validation に仕様ファイルを要求しない**
  #   （仕様ファイルは spec 段の番号で作られるので、引きようがない）
  case "$kind" in
    survey)     check_survey_file "$n";;
    spec)       check_spec_file "$n"; check_auto_decisions "$n";;
    experiment) check_experiment_set "$n";;
    feature|validation|bug|docs|refactor|chore) ;;
    *)          fail "issue: 未知の段の種類 '$kind'";;
  esac
}

# ★ 「#N の作業は既に main に入っているか」だけを見る。
#   issue-finish.sh の再入（マージ済み・issue は open・worktree は消えた）の判定に使う。
#   述語を呼び出し側で書き直さないためにモードとして出す。
mode_merged() {
  info "#$1 の作業が既定ブランチに入っているか"
  check_merged_commit "$1"
}

mode_merge() {
  local n="$1" kind="$2" branch_n="${3:-}"
  [ -n "$branch_n" ] || branch_n="$n"
  info "マージ直前の検査 (#$n [$kind]。ブランチは #$branch_n で見る)"
  check_branch "$branch_n"
  check_commit_link "$n"
  check_no_closes "$n"
  check_pr_review
  gates conformance "$n" "$kind"
}

# markdown を読むゲート（goal・判定の形・仕様整合・全部 negative）は python 側が単一情報源。
# ★ 終了コード 2（gh・git の失敗）を FAIL と区別して出す
gates() {
  local rc=0
  python3 -B "$(dirname "${BASH_SOURCE[0]}")/check-discipline-gates.py" "$@" || rc=$?
  RAN_ANY=1
  case "$rc" in
    0) ;;
    1) FAILED=1;;
    *) FAILED=1; printf '!!! FAILED: %s の検査そのものが失敗した（exit %s。上の出力を見ること）\n' "$1" "$rc";;
  esac
}

# ★ 「この epic に紐づかない」ではなく「**どの issue にも紐づかない**」を数える。
#   前者は他 epic の正常な作業を全部違反として数え、実測 245/245 で情報量が 0 だった。
mode_epic() {
  local epic="$1" base since orphan=0 total=0 sha subj
  base="$(resolve_base)" || { fail "epic: base ref を解決できない"; return; }
  since="$(gh issue view "$epic" --json createdAt -q .createdAt 2>/dev/null || true)"
  [ -n "$since" ] || { fail "epic: #$epic の createdAt を取得できない（gh の失敗を通さない）"; return; }
  info "epic #$epic 作成（$since）以降、**どの issue にも紐づかない** main のコミットを数える"
  # ★ merge commit は本文に Refs を持たないのが正常なので外す。
  #   ★ サブプロセスを 1 回にする（旧実装は 245×N 回で 8.4 秒かかっていた）
  # ★ **コミット本文は複数行になる。** `-z` で NUL 区切りにして 1 コミット 1 エントリにする
  #   （改行で読むと本文の途中で切れ、実測で 0/0 件になった）
  local entry
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
    sha="${entry%%$'\t'*}"; subj="${entry#*$'\t'}"
    total=$((total + 1))
    [[ "$subj" =~ (Refs|Fixes)[[:space:]]*\#[0-9]+ ]] && continue
    orphan=$((orphan + 1))
    printf '    紐づかない: %s %s\n' "${sha:0:8}" "${subj%%$'\n'*}"
  done < <(git log "$base" --no-merges --since="$since" -z \
             --format=$'%H\t%s %b' 2>/dev/null || true)
  RAN_ANY=1
  printf '  issue に紐づかないコミット: %d / %d 件\n' "$orphan" "$total"
}

# 達成判定コメントと完了条件の照合
mode_verdict() {
  local epic="$1" body comment item n_items=0
  body="$(gh issue view "$epic" --json body -q .body 2>/dev/null || true)"
  [ -n "$body" ] || { fail "verdict: #$epic の本文を取得できない"; return; }
  comment="$(gh issue view "$epic" --json comments \
              -q '[.comments[]|select(.body|contains("## 判定"))]|last|.body' 2>/dev/null || true)"
  if [ -z "$comment" ] || [ "$comment" = "null" ]; then
    fail "verdict: '## 判定' の見出しを含むコメントが #$epic に無い"; return
  fi
  info "達成判定コメントと完了条件を照合（#$epic）"
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    n_items=$((n_items + 1))
    if [[ "$comment" == *"$item"* ]]; then
      pass "完了条件が引用されている: ${item:0:40}"
    else
      fail "完了条件が引用されていない: ${item:0:60}"
    fi
  # 項目 = 行頭のチェックボックス（`- [ ]`）か番号付き列挙（`0.` `1.` …）の見出し行。
  # 字下げされた継続行・入れ子の箇条書きは項目にしない
  done < <(printf '%s' "$body" | awk '
      { sub(/\r$/, "") }
      /^##[[:space:]]*完了条件/ { inside=1; next }
      inside && /^##/ { inside=0 }
      inside && (/^-[[:space:]]*\[[ xX]\]/ || /^[0-9]+\.[[:space:]]/) {
        sub(/^(-[[:space:]]*\[[ xX]\]|[0-9]+\.)[[:space:]]*/, ""); if (length($0)) print }')
  # ★ 0 項目は「照合できない」。通さない
  [ "$n_items" -gt 0 ] || fail "verdict: #$epic の完了条件が 0 項目（照合できないので通さない）"
  gates all-negative "$epic"
}

# ══════════════════════════════════════════════════════════════════

[ $# -ge 1 ] || usage
case "$1" in
  artifacts) [ $# -eq 3 ] || usage; mode_artifacts "$2" "$3";;
  issue)     [ $# -ge 3 ] && [ $# -le 4 ] || usage; mode_issue "$2" "$3" "${4:-}";;
  merge)     [ $# -ge 3 ] && [ $# -le 4 ] || usage; mode_merge "$2" "$3" "${4:-}";;
  goal)      [ $# -eq 2 ] || usage; info "goal の検査 (task #$2)"; gates goal "$2";;
  verdict-task) [ $# -eq 2 ] || usage; info "task の判定の形 (task #$2)"; gates verdict-task "$2";;
  merged)    [ $# -eq 2 ] || usage; mode_merged "$2";;
  epic)      [ $# -eq 2 ] || usage; mode_epic "$2";;
  verdict)   [ $# -eq 2 ] || usage; mode_verdict "$2";;
  *) usage;;
esac

if [ "$RAN_ANY" = 0 ]; then
  printf '!!! 検査が 1 つも走らなかった\n'
  exit 1
fi
exit "$FAILED"
