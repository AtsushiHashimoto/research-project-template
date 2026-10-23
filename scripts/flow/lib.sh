#!/usr/bin/env bash
#
# scripts/flow/*.sh の共通部分。**述語はここに書かない**（単一情報源は
# scripts/check-discipline.sh）。ここに置くのは入出力と gh の薄い包みだけ。
#
# 使い方: 各スクリプトの先頭で
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ★ **`-e` を入れる。** これが無いと、`$(...)` の中で `die` しても
#   サブシェルが終わるだけで**呼び出し元は空文字列を受け取って続行する**。
#   実測: 存在しない issue の state が空になり、**closed 扱いで素通り**した。
#   epic-cycle では open な sub-epic / task が無視され、葉の判定が丸ごと迂回される。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly CHECK="$REPO_ROOT/scripts/check-discipline.sh"
readonly QUALITY="$REPO_ROOT/scripts/quality-check.sh"
readonly PREDICATES="$REPO_ROOT/scripts/check-discipline-predicates.sh"

# ★ 「マージは済んだが後片付けで失敗した」ことを表す終了コード。
#   送り手（flow/commit.sh）と受け手（flow/issue-finish.sh）が**同じ定数を読む**。
#   裸の 10 を書き写すと、片方だけ直したときに「マージが失敗した」という嘘に戻る。
#   ★ **テストは 10 を直書きする**（tests/test_commit_flow.sh）。定数を読ませると、
#     値を変えた瞬間に検査が黙って追随して恒真になるので、独立オラクルのままにする。
# shellcheck disable=SC2034  # 参照は commit.sh / issue-finish.sh 側（lib.sh は定義だけ）
readonly POST_MERGE_FAILED=10

# ★ ブランチの type の一覧は **check-discipline-predicates.sh の BRANCH_TYPES が単一情報源**。
#   ここに書き写すと 4 箇所（predicates / issue-start の 2 箇所 / issue-branch）に分かれるので、
#   **そのファイルから読む**。branch_prefix の値の集合と一致することはテストが固定する。
BRANCH_TYPES="$(sed -n 's/^readonly BRANCH_TYPES="\(.*\)"$/\1/p' "$PREDICATES")"
[ -n "$BRANCH_TYPES" ] || { printf '!!! %s から BRANCH_TYPES を読めない\n' "$PREDICATES" >&2; exit 1; }
readonly BRANCH_TYPES

# ★ 「作業してはいけないブランチ」の集合も predicates から読む（書き写さない）。
#   実体は check_branch の `case "$b" in main|master)`。
# shellcheck disable=SC2016  # `$b` は**被参照ファイルの中の綴り**なので展開させない
PROTECTED_BRANCHES="$(sed -n 's/^[[:space:]]*case "\$b" in \([a-z|]*\)).*/\1/p' "$PREDICATES")"
[ -n "$PROTECTED_BRANCHES" ] || { printf '!!! %s から PROTECTED_BRANCHES を読めない\n' "$PREDICATES" >&2; exit 1; }
# ★ predicates 側に `case` 行が 2 本できると複数行になり、`[[ =~ ^(…)$ ]]` がどのブランチにも
#   一致しなくなって**保護が黙って消える**。1 行であることまで見る
if [[ "$PROTECTED_BRANCHES" == *$'\n'* ]]; then
  printf '!!! %s から保護ブランチを 2 行以上読んでしまった。抽出を直すこと\n' "$PREDICATES" >&2
  exit 1
fi
readonly PROTECTED_BRANCHES

# ── 出力 ────────────────────────────────────────────────────────
say()  { printf '%s\n' "$*"; }
head2(){ printf '\n── %s ──────────────────────────────\n' "$*"; }
# ★ **サブシェルの中から呼ばれても親ごと落とす**。`exit 1` だけでは
#   `$(...)` を抜けるだけで済んでしまう
# ★ 親を落とすが、**終了コードは 1 に揃える**（TERM だと 143 になり
#   「検査が落ちた」と「殺された」を呼び出し側が区別できない）
trap 'exit 1' TERM
die()  { printf '\n!!! %s\n' "$*" >&2; kill -TERM $$; exit 1; }

# ★ **「次に何をせよ」は 1 箇所で出す。** 各スクリプトが好きな形で書くと、
#   読み手（モデル）が要約して飛ばす余地ができる。
# next      … 段が進んだ。**0 で終わる**
# next_fail … 前提が揃っていない。**1 で終わる**
#   ★ 両方 0 で終えると、上位（epic-cycle）から見て常に成功になり、
#     「規律違反を検出した」ことが呼び出し側に伝わらない。
# next_final … 区切り。**末尾の「もう一度呼ぶこと」を付けない。0 で終わる**
#   （付けると /compact の直後に再呼び出しを促し、引き継ぎが二重に書かれる。
#     0 でないと epic-cycle.sh が task-run.sh の終了コードをそのまま返して止まる）
_next_open()  { printf '\n════════════════════════════════════════════\n次にやること:\n\n'; printf '%s\n' "$@"; }
_next_close() { printf '════════════════════════════════════════════\n'; }
_next_body() {
  _next_open "$@"
  printf '\n終わったら、もう一度このスクリプトを同じ引数で呼ぶこと。\n'
  _next_close
}
next()       { _next_body "$@"; exit 0; }
next_fail()  { _next_body "$@"; exit 1; }
next_final() { _next_open "$@"; _next_close; exit 0; }

# ★ 区切りの引き継ぎ手順。task-run / issue-finish / epic-cycle の 3 箇所と
#   .claude/rules/template/deliverables.md が指す**文言の単一情報源**。
#   ★ /clear ではなく /compact: /clear すると再開に使う番号が会話から消える。
#   見出しは scripts/handoff.sh の REQUIRED が単一情報源なので**ここに書き写さない**
handoff_steps() {  # handoff_steps <書き先の番号> [<task-run|epic-cycle|-> [<再開の番号>]]（- は再開なし）
  local resume="bash scripts/flow/${2:-task-run}.sh ${3:-$1}" tail
  if [ "${2:-}" = - ]; then tail="。"; else tail="。再開は \`$resume\`"; fi
  printf '%s\n' \
    "  区切りの引き継ぎ（メインが行う。ワーカーは行わない）:" \
    "  H1. bash scripts/handoff.sh write $1 - で #$1 に引き継ぎを書く" \
    "      （見出しは scripts/handoff.sh の REQUIRED。欠けると投稿を拒まれる）"
  [ "${2:-}" = - ] || printf '%s\n' "      ### 次の一手 には再開コマンド \`$resume\` を書く"
  printf '%s\n' "  H2. ユーザーに 1 行で「区切りです。/compact をどうぞ$tail」と伝える"
}
# epic-cycle から降りた task-run が区切りで終わったときに足す 1 行（/compact の文言をここに留める）
epic_return_step() {  # epic_return_step <epic番号>
  printf '%s\n' "  ★ task の完了判定と引き継ぎの後、もう一度 \`bash scripts/flow/epic-cycle.sh $1\` を呼ぶ（/compact はその後）"
}

# ── gh（失敗を黙って通さない）──────────────────────────────────
gh_repo() {
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
    || die "gh repo view が失敗した。認証とネットワークを確認すること"
}

# gh_json <説明> <gh の引数...>  — 失敗したら die する
# ★ **stderr を値に混ぜない**。旧実装は `2>&1` だったため、
#   gh が更新通知を 1 行 stderr に出すだけで**値が壊れた**
#   （ラベル列に混ざって kind_of が空になる / PR の件数が 9 件に化ける）。
# ★ **`if out=$(...)` で受ける。** `out="$(...)"; rc=$?` は `set -e` 下で
#   代入が失敗した時点でシェルが終わり、**die に到達しない**（実測: rc=7・出力なし）。
#   捕獲されずに呼ばれた場合、呼び出し側は「規律違反の 1」と区別できない値を受け取る。
gh_json() {
  local what="$1"; shift
  local out rc err msg
  err="$(mktemp)"
  if out="$("$@" 2>"$err")"; then rc=0; else rc=$?; fi
  if [ "$rc" -ne 0 ]; then
    msg="$(cat "$err")"; rm -f "$err"
    die "$what が失敗した（exit $rc）: ${msg:0:200}"
  fi
  rm -f "$err"
  printf '%s' "$out"
}

# ── issue の情報 ────────────────────────────────────────────────
issue_labels() { gh_json "issue #$1 のラベル取得" gh issue view "$1" --json labels -q '[.labels[].name]|join(",")'; }
issue_state()  { gh_json "issue #$1 の状態取得"   gh issue view "$1" --json state  -q '.state'; }
issue_title()  { gh_json "issue #$1 の題名取得"   gh issue view "$1" --json title  -q '.title'; }

# ★ パイプを使わない（pipefail 下で生産者が SIGPIPE で死ぬ）
has_label() { case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }

# sub_issues を番号の並びで返す
sub_issues() {
  local repo; repo="$(gh_repo)"
  gh_json "#$1 の sub_issues 取得" gh api "repos/$repo/issues/$1/sub_issues" --jq '.[].number'
}

# open な sub_issue の番号（★ `// empty` を付けて「無い」を空にする）
sub_issues_open() {
  local repo; repo="$(gh_repo)"
  gh_json "#$1 の open な sub_issues 取得" \
    gh api "repos/$repo/issues/$1/sub_issues" --jq '.[]|select(.state=="open")|.number'
}

# 親 issue の番号。無ければ空
issue_parent() {
  gh_json "#$1 の親取得" gh issue view "$1" --json parent -q '.parent.number // empty'
}

# ★ ブランチに使う番号 = 親が task ならその番号、そうでなければ自分
task_of() {
  local n="$1" p
  p="$(issue_parent "$n")"
  if [ -n "$p" ] && has_label "$(issue_labels "$p")" task; then printf '%s' "$p"
  else printf '%s' "$n"; fi
}

# 種類ラベル → ブランチ接頭辞（**ここが単一情報源**）
# ★ 戻り値は check_branch の BRANCH_TYPES（check-discipline-predicates.sh の BRANCH_TYPES）に収まること
# ★ 表に無い種類は空を返す。呼び出し側は停止する（既定の接頭辞に丸めない）
branch_prefix() {
  case "$1" in
    feature)       printf 'feature';;
    chore)         printf 'chore';;   # quick.sh が chore の枝を chore/ で作る
    spec)          printf 'spec';;
    bug)           printf 'fix';;
    survey)        printf 'survey';;
    experiment)    printf 'experiment';;
    validation)    printf 'validation';;
    docs)          printf 'docs';;
    refactor)      printf 'refactor';;
    *)             printf '';;
  esac
}

# ★ いまのブランチの open な PR を 1 つだけ返す（2 箇所に同じ実装があった）。
#   **`.[0]` で黙って選ばない。** 2 本以上あれば die する
open_pr_for() {  # open_pr_for <ブランチ> <呼び出し元の説明>
  local branch="$1" what="$2" prs p n=0 pr=""
  prs="$(gh_json "open な PR の取得" \
          gh pr list --head "$branch" --state open --json number --jq '.[].number')"
  for p in $prs; do n=$((n + 1)); pr="$p"; done
  [ "$n" -le 1 ] || die "同じブランチ（$branch）に open な PR が $n 本ある: $prs
$what"
  printf '%s' "$pr"
}

# ── git（worktree の中から呼ばれても main を指す）────────────────
# ★ `| head` を使わない（pipefail 下で生産者が SIGPIPE で死ぬ）
main_repo() {
  local line
  while IFS= read -r line; do
    case "$line" in worktree\ *) printf '%s' "${line#worktree }"; return 0;; esac
  done < <(git worktree list --porcelain 2>/dev/null || true)
  die "メインリポジトリのパスを解決できない（git worktree list が失敗した）"
}

# ★ 既定ブランチは main 固定（.claude/rules/template/git-workflow.md）。
#   基点の解決は scripts/check-discipline.sh の resolve_base と同じ順（origin/main → main）。
#   lib.sh は check-discipline.sh を外部実行しているので関数を source できない。
#   **2 箇所にあることを黙らない。変えるときは両方直す。**
readonly DEFAULT_BRANCH=main
# ★ die しない版。`start_point` の `die` は `kill -TERM $$` で**親ごと落とす**ので、
#   `$(start_point 2>/dev/null || true)` では捕まえられない。
#   マージ後のように「失敗しても独自の終了コードを返したい」場所はこちらを使う。
start_point_or_empty() {
  local cand
  for cand in "origin/$DEFAULT_BRANCH" "$DEFAULT_BRANCH"; do
    if git rev-parse --verify --quiet "$cand" >/dev/null; then printf '%s' "$cand"; return 0; fi
  done
  printf ''
}

start_point() {
  local b; b="$(start_point_or_empty)"
  [ -n "$b" ] || die "基点のブランチを解決できない（origin/$DEFAULT_BRANCH も $DEFAULT_BRANCH も無い）"
  printf '%s' "$b"
}

# ★ 枝を既定ブランチに合わせ直す。**squash merge は元のコミットを残さない**ので、
#   枝を task 単位で使い回すと、1 回目の squash 以降、枝側のコミットは
#   「main に入っていない」ままになり **2 番目以降の子で必ず衝突する**（実測）。
#   ★ **呼ぶのはマージの後**。ここで失敗しても「マージが失敗した」ではない。
#   ★ 触ってよいのは「汚れておらず、内容が origin/<既定> と同じ」ときだけ。
realign_branch() {  # realign_branch <worktree> <ブランチ> → 0 成功 / 1 触らなかった（理由を出力）
  local wt="$1" br="$2" base
  base="$(start_point_or_empty)"; base="${base#origin/}"
  [ -n "$base" ] || { say "!!! 既定ブランチを解決できず、合わせ直していない"; return 1; }
  # ★ reset --hard は未コミットの変更を消す。汚れていたら触らない
  [ -z "$(git -C "$wt" status --porcelain)" ] \
    || { say "!!! worktree が汚れているので合わせ直していない"; return 1; }
  git -C "$wt" fetch -q origin "$base" \
    || { say "!!! origin/$base を取得できず、合わせ直していない"; return 1; }
  # ★ 内容が違うなら触らない（squash 済みなら差分は無いはず）
  git -C "$wt" diff --quiet "origin/$base" HEAD \
    || { say "!!! 枝に origin/$base と違う内容が残っているので合わせ直していない"; return 1; }
  git -C "$wt" reset --hard -q "origin/$base" \
    || { say "!!! reset --hard に失敗した"; return 1; }
  git -C "$wt" push -q --force-with-lease origin "$br" \
    || { say "!!! origin/$br を更新できなかった（force-with-lease が拒否された）"; return 1; }
  say "  ok   $br を origin/$base に合わせた（内容は同じ。履歴だけ揃えた）"
}

# ── 既定順（.claude/rules/template/issue-hierarchy.md）────────────
# ★ この並びが単一情報源。**2 箇所に書かない**
readonly DEFAULT_ORDER="survey spec feature validation experiment"
# 既定 5 段の後に番号順で処理する種類（ここが単一情報源）
readonly EXTRA_ORDER="bug docs refactor chore"

# kind_of <ラベル列> → 種類ラベル 1 つ。無ければ空
kind_of() {
  local labels="$1" k
  for k in $DEFAULT_ORDER $EXTRA_ORDER; do
    has_label "$labels" "$k" && { printf '%s' "$k"; return; }
  done
  printf ''
}

# ── 品質チェック（lib-quality.sh）────────────────────────────────
# shellcheck source=scripts/flow/lib-quality.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-quality.sh"

# ★ **マージは済んでいる**ことを必ず言ってから抜ける。
#   `next_fail` は使えない。末尾に「もう一度同じ引数で呼ぶこと」を必ず付けるが、
#   マージ後の再実行は check merge か gh pr merge で落ちるので**誤った指示**になる。
#   出力は die と同じく stderr（同じ `!!!` の印で流れ先が分かれると、一番重要な行だけ消える）。
post_merge_fail() {  # post_merge_fail <何が失敗したか> [<後片付けの手順>...]
  local what="$1" line; shift
  {
    printf '\n!!! %s\n' "$what"
    printf '!!! **マージは済んでいる。** 失敗したのは後片付けだけなので、マージし直さないこと\n'
    for line in "$@"; do printf '     %s\n' "$line"; done
  } >&2
  exit "$POST_MERGE_FAILED"
}

# ★ `check merge` が落ちたときの案内。**2 箇所に書くと内容がずれる**
merge_check_hints() {  # merge_check_hints <N> <TASK>
  printf '%s\n' \
    "  1. ブランチ <type>/$2-* に居ること" \
    "  2. 'Refs #$1' を持つコミットがあること" \
    "  3. PR があり、本文に '## /review 結果' とその中身があること" \
    "     （/review を回し、各サブエージェントの判定を書く。要約で済ませない）"
}

check() { bash "$CHECK" "$@"; }

# ── 共著者の行（★ 定数。環境変数で変えない）──────────────────────
# shellcheck disable=SC2034  # 参照は commit.sh / quick.sh 側
readonly CO_AUTHOR="Co-Authored-By: Claude <noreply@anthropic.com>"

# ── task 単位でない issue のブランチ名の slug ──────────────────────
# 題名の ASCII 英数字だけを使う（日本語の題名は空になるので種類名で埋める）
slug_of() {  # slug_of <題名> <代わりの語>
  local t s
  t="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' '-')"
  s="$(printf '%s' "$t" | LC_ALL=C tr -s '-')"; s="${s#-}"; s="${s:0:30}"; s="${s%-}"
  printf '%s' "${s:-$2}"
}
