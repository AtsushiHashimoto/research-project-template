#!/usr/bin/env bash
#
# コミット層。**散文の手順（commit-only / commit-push / commit-merge）をここに移した**。
#
#   bash scripts/flow/commit.sh only  --issue <N> --message <題>
#   bash scripts/flow/commit.sh push  --issue <N> --message <題>
#   bash scripts/flow/commit.sh merge <N> [<TASK>] [<worktree>]
#
# ★ **stage はしない。** 呼び出し側が `git add <名前>` で意図したファイルだけを stage する
#   （`git add -A` は未追跡の clone・生成物を混ぜる。.claude/rules/template/git-workflow.md）。
#   only / push の 3 通り: stage 済み → コミット / 変更なし・未 push あり → push だけ /
#   未 stage・未追跡だけ → 停止（一覧と `git add` の例を出す）
#
# ★ `merge` は **worktree の中から呼ぶ**。`check-discipline.sh merge` の 3 述語は
#   現在の HEAD / ブランチを見るので、メインリポジトリへ移った後では必ず落ちる。
#   メインリポジトリへの `cd` は**このスクリプトが自分で行う**。
#
# 終了コード: 0 成功 / 1 前提が揃っていない・失敗 /
#   **$POST_MERGE_FAILED（=10、lib.sh）マージは済んだが後片付けで失敗**
#   （呼び元が「マージが失敗した」と嘘を書かないため）

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -ge 1 ] || die "使い方: bash scripts/flow/commit.sh <only|push|merge> ..."
SUB="$1"; shift

# ── 共通: ブランチと issue の検査 ───────────────────────────────
# ★ 型の一覧は書き写さない。$BRANCH_TYPES（lib.sh が predicates から読む）を使う
current_branch() {
  local b
  b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$b" ] || die "detached HEAD では実行できない"
  # ★ 集合は predicates.sh から読む（$PROTECTED_BRANCHES。書き写さない）
  [[ ! "$b" =~ ^($PROTECTED_BRANCHES)$ ]] \
    || die "ブランチ: $b に居る。issue のブランチで実行すること"
  [[ "$b" =~ ^($BRANCH_TYPES)/[0-9]+- ]] \
    || die "ブランチ '$b' が <type>/<番号>-* の形でない（type は $BRANCH_TYPES）"
  printf '%s' "$b"
}

# ★ --issue の番号は**引数で受け取る**。ブランチ名は task 番号なので使えない
#   （ブランチは <type>/<TASK>-i<N> で、同じブランチを task 内の全段が共有する）
require_open_issue() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "--issue の値が数値でない: '$1'"
  # ★ 「番号が違う」だけを疑わせない。マージ後に close 済みの番号で
  #   やり直したときに、この文言が的外れな誘導になる
  [ "$(issue_state "$1")" = OPEN ] \
    || die "#$1 は open でない（既に close 済みか、番号が違う）。
マージが済んでいるかは bash scripts/check-discipline.sh merged $1 で確かめること"
}

# ══════════════════════════════════════════════════════════════════
# only / push
# ══════════════════════════════════════════════════════════════════
do_commit() {  # do_commit <push するか 0/1> <引数...>
  local do_push="$1"; shift
  local sub=only; [ "$do_push" = 0 ] || sub=push
  local N="" MSG=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue)   [ $# -ge 2 ] || die "--issue に値が無い";   N="$2"; shift 2;;
      --message) [ $# -ge 2 ] || die "--message に値が無い"; MSG="$2"; shift 2;;
      *) die "未知の引数: $1
使い方: bash scripts/flow/commit.sh $sub --issue <N> --message <題>";;
    esac
  done
  [ -n "$N" ]   || die "--issue が無い（ブランチ名からは取らない。ブランチは task 番号）"
  [ -n "$MSG" ] || die "--message が無い。**何を変えたかを 1 行で書くこと**（スクリプトは文言を作らない）"
  require_open_issue "$N"

  local branch; branch="$(current_branch)"
  head2 "コミット（#$N / $branch）"

  local staged rest unpushed
  staged="$(git diff --cached --name-only)" || die "git diff --cached が失敗した"
  rest="$(git status --porcelain)" || die "git status が失敗した"
  # upstream が無ければ「未 push がある」とみなす（安全側）
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    unpushed="$(git rev-list --count '@{u}..HEAD')"
  else
    unpushed="1"
  fi

  if [ -n "$staged" ]; then
    git diff --cached --stat
    git commit -m "$MSG

Refs #$N

$CO_AUTHOR" || die "git commit が失敗した"
    say "  ok   コミットした（$(git rev-parse --short HEAD)）"
    rest="$(git status --porcelain)" || die "git status が失敗した"
    [ -z "$rest" ] || { say "  !!   stage しなかった変更が残っている（コミットに入れていない）:"; git status --short; }
  elif [ -n "$rest" ]; then
    git status --short
    next_fail "#$N: stage されたファイルが無い（未 stage・未追跡の変更だけがある）。" "" \
      "  コミットに入れるファイルを**名前で** stage すること（-A や . で一括 stage しない）:" \
      "    git add <ファイル名> [<ファイル名>...]" \
      "  上の一覧のうち、入れるべきものだけを選ぶ。生成物・clone は入れない"
  elif [ "$do_push" = 1 ] && [ "${unpushed:-0}" -gt 0 ]; then
    say "  --   作業ツリーに変更は無い（未 push のコミットがあるので push だけ行う）"
  else
    die "作業ツリーに変更が無い（空コミットは作らない）"
  fi

  if [ "$do_push" = 1 ]; then
    git push -u origin "$branch" || die "git push が失敗した"
    say "  ok   push した（origin/$branch）"
    next "#$N をコミットして push した。" "" \
      "  完了なら bash scripts/flow/issue-finish.sh $N"
  fi
  next "#$N をコミットした（push していない）。" "" \
    "  push するなら bash scripts/flow/commit.sh push --issue $N --message <題>" \
    "  完了なら     bash scripts/flow/issue-finish.sh $N"
}

# ══════════════════════════════════════════════════════════════════
# merge
# ══════════════════════════════════════════════════════════════════
do_merge() {
  local N="${1:-}" TASK="" WT=""
  [ -n "$N" ] || die "使い方: bash scripts/flow/commit.sh merge <N> [<TASK>] [<worktree>]"
  [[ "$N" =~ ^[0-9]+$ ]] || die "issue 番号が数値でない: '$N'"
  shift
  # ★ 第 2 引数が数値でなければ worktree とみなす（パスが TASK に化けるのを防ぐ）
  if [ $# -gt 0 ]; then
    if [[ "$1" =~ ^[0-9]+$ ]]; then TASK="$1"; shift; fi
  fi
  [ $# -eq 0 ] || { WT="$1"; shift; }
  [ $# -eq 0 ] || die "引数が多い: $*"
  # ★ 順序: **ローカルで済む検査を先に**（ブランチ）→ 次に gh を叩く。
  #   `require_open_issue` は `task_of` より前（存在しない番号だと「親取得が失敗した」という
  #   分かりにくい die が先に出る）
  local branch kind; branch="$(current_branch)"
  require_open_issue "$N"   # ★ only/push と揃える（closed な issue はマージまで進めない）
  [ -n "$TASK" ] || TASK="$(task_of "$N")"
  kind="$(kind_of "$(issue_labels "$N")")"
  [ -n "$kind" ] || die "#$N が種類ラベルを持たない"
  head2 "マージ（#$N / task #$TASK / $branch）"
  say "  ..   マージ直前の検査は issue-finish.sh 経由なら 2 回目（単独で叩けるよう commit.sh 側でも見る）"

  # ── 段 2. マージ直前の検査（★ 品質チェックより先。規律違反に品質チェックの時間を払わせない）──
  check merge "$N" "$kind" "$TASK" || next_fail \
    "#$N: マージ直前の検査が通らない（上の FAILED を見ること）。" \
    "" \
    "$(merge_check_hints "$N" "$TASK")"

  # ── 段 2a. ★ コミットしていない変更が無いこと ──
  # 段 8 の `git worktree remove --force` は、**未コミットの変更があっても消す**
  #   （`--force` はその拒否を上書きするためのもの）。未 push のコミットと同じ経路で、
  #   同じように失われる。`run_quality` の記録は dirty なら再実行するだけで、止めない。
  local dirty
  dirty="$(git status --porcelain)" \
    || die "git status が失敗した（作業ツリーの状態を確かめられない）"
  [ -z "$dirty" ] || next_fail \
    "#$N: コミットしていない変更がある。worktree は --force で消えるので**失われる**。" "" \
    "  1. git add <ファイル名> で入れるものを stage し、bash scripts/flow/commit.sh push --issue $N --message <題>" \
    "     入れないもの（生成物等）は消すか .gitignore に足す" \
    "  2. 追加分を /review に掛け、PR 本文の '## /review 結果' を更新する"

  # ── 段 2b. ★ 未 push のコミットが無いこと ────────────────────
  # squash merge は **origin 側のブランチ**を畳む。ローカルにしか無いコミットは
  # 載らないまま、段 8 で worktree が `--force` で消える（＝**そのコミットは失われる**）。
  # `check_commit_link` はローカルの base..HEAD を見るので、この穴を塞げない。
  # **push はしない**（PR に後から足すと、PR 本文の /review 結果が実際の中身と食い違う）。
  git fetch -q origin "$branch" 2>/dev/null || true
  local ahead=0
  if ! git rev-parse --verify --quiet "origin/$branch" >/dev/null; then
    # ★ 「引けない」を 0 と読まない。PR がある以上 origin に枝はあるはずで、
    #   無いなら**一度も push していない**か fetch が失敗している
    next_fail \
      "#$N: origin に $branch が無い。マージする中身が origin 側に存在しない。" "" \
      "  1. bash scripts/flow/commit.sh push --issue $N --message <題>" \
      "  2. PR が無ければ gh pr create で作る（本文に '## /review 結果'）" \
      "  3. オフラインなら、git fetch origin $branch が通る状態にしてから戻ること" \
      "     （判定に使うのはローカルの origin/$branch。fetch できないと古いまま見える）"
  fi
  # ★ ここも「引けない」を 0 と読まない（直前の rev-parse を通っているので本来は失敗しない）
  ahead="$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null)" \
    || die "origin/$branch..HEAD を数えられない（git の失敗を「差分なし」と読まない）"
  [ "$ahead" -eq 0 ] || next_fail \
    "#$N: ローカルにしか無いコミットが $ahead 件ある。このままマージすると**失われる**。" "" \
    "  1. bash scripts/flow/commit.sh push --issue $N --message <題>" \
    "  2. 追加分を /review に掛け、PR 本文の '## /review 結果' を更新する" \
    "     ★ push だけでは足りない。PR 本文のレビュー結果が、いま足した分を見ていない" \
    "       中身のままになり、**レビューを通っていないコードがマージされる**"

  # ── 段 3. 品質チェック（★ 記録の判断は run_quality の中）──
  run_quality "$kind"

  # ── 段 4. PR 番号（★ 述語は lib.sh:open_pr_for に 1 つだけ）──
  local PR
  PR="$(open_pr_for "$branch" "どれをマージするか決めてから呼び直すこと")"
  [ -n "$PR" ] || next_fail \
    "#$N: ブランチ $branch に open な PR が無い。" "" \
    "  1. git push -u origin $branch" \
    "  2. gh pr create で PR を作る（本文に '## /review 結果'）"

  # ── 段 5. メインリポジトリへ（★ ここから先は worktree を消しても安全）──
  local MAIN; MAIN="$(main_repo)"
  local wt_branch=""
  if [ -n "$WT" ]; then
    # ★ 実パスに正規化してから比較する（`.` や末尾スラッシュ、symlink で素通りさせない）
    WT="$(cd "$WT" 2>/dev/null && pwd -P)" || die "worktree が見つからない: $WT"
    [ "$WT" != "$MAIN" ] || die "メインリポジトリのパスを worktree として渡してはいけない（$WT）"
    wt_branch="$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    # ★ **いまマージするブランチの worktree であることを確かめる**。
    #   これが無いと、無関係な worktree とそのブランチを --force で消せてしまう
    [ "$wt_branch" = "$branch" ] \
      || die "渡された worktree のブランチ（$wt_branch）が、いまマージするブランチ（$branch）と違う。
消す対象を取り違えている可能性が高いので中断する: $WT"
  fi
  cd "$MAIN" || die "メインリポジトリ $MAIN へ移れない"

  # ── 段 6. squash merge ──────────────────────────────────────
  head2 "PR #$PR を squash merge"
  gh pr merge "$PR" --squash || die "gh pr merge が失敗した（マージしていない）"
  say "  ok   PR #$PR を squash merge した（★ ここから先が失敗しても、マージは取り消されない）"

  # ★ ここから先の失敗は「マージは済んでいる」。終了コードを分ける
  # ── 段 7. 既定ブランチ（main 固定）の更新 ─────────────────────
  # ★ マージ後なので、ここから先の失敗はすべて exit 10（die=1 で抜けると呼び元が嘘を書く）。
  #   **`start_point` は使えない**（die が kill -TERM $$ で親ごと落とすので `|| true` が効かず、
  #   exit 1 になって「マージが失敗した」の嘘に戻る）
  local base
  base="$(start_point_or_empty)"; base="${base#origin/}"
  [ -n "$base" ] || post_merge_fail "既定ブランチを解決できない" \
    "origin/$DEFAULT_BRANCH も $DEFAULT_BRANCH も無い。git fetch origin $DEFAULT_BRANCH で取ること"
  git checkout "$base" || post_merge_fail "$base へ切り替えられない" \
    "git -C $MAIN status で作業ツリーの状態を確かめること"
  # ★ remote と枝を明示する。素の `git pull` は
  #   既定ブランチに upstream が設定されていない環境で必ず落ちる
  git pull --ff-only origin "$base" \
    || post_merge_fail "$base の更新に失敗した" \
       "git -C $MAIN pull --ff-only origin $base をやり直すこと（マージ自体は済んでいる）"

  # ── 段 8. 後片付け（★ 「もう無い」と「消せなかった」を分ける）──
  if [ -z "$WT" ]; then
    say "  --   worktree は指定されていないので残す"
    next "#$N をマージした（PR #$PR）。worktree は残した。"
  fi

  if [ -d "$WT" ]; then
    # ★ 削除は scripts/worktree-relative.sh remove だけを通す（add が lock するので、unlock してから消す。
    #   失敗したら lock し直してくれる）
    bash "$MAIN/scripts/worktree-relative.sh" remove "$WT" --force \
      || post_merge_fail "worktree を消せない: $WT" "bash scripts/worktree-relative.sh remove $WT --force をやり直すこと"
    say "  ok   worktree を削除した（$WT）"
  else
    say "  --   worktree は既に無い（$WT）"
  fi

  # ★ ここに来る時点でブランチは <type>/<N>-* の形（current_branch が強制）なので、
  #   既定ブランチと一致し得ない。
  # ★ ここは**無条件**。`[ -n "$wt_branch" ]` も `!= "$base"` も恒真で、
  #   偽になったときに `else` が無いまま「片付けた」と報告してしまう形だった。
  #   代わりに、**消してはいけない枝を消さない**ことだけを明示の assertion で守る
  #   （今日は current_branch が <type>/<N>-* を強制するので発火しないが、
  #     既定ブランチが `feature/1-x` のような名前に変わると発火する）
  [ "$branch" != "$base" ] \
    || post_merge_fail "いま片付けようとしている枝（$branch）が既定ブランチと同じ" \
       "既定ブランチを消すところだった。手で worktree だけ片付けること"

  # ★ `--exit-code` は「一致なし」=2、通信失敗=128。**区別する**（
  #   オフラインを「もう無い」と読むと origin に枝が残る）
  local ls_rc=0
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 || ls_rc=$?
  case "$ls_rc" in
    0) git push origin --delete "$branch" \
         || post_merge_fail "リモートブランチを消せない: $branch" \
            "git push origin --delete $branch をやり直すこと"
       say "  ok   リモートブランチを削除した（$branch）";;
    2) say "  --   リモートブランチは既に無い（$branch）";;
    *) post_merge_fail "origin を引けない（exit $ls_rc）。リモートブランチの状態が分からない" \
         "通信を確かめてから git ls-remote --heads origin $branch を見ること";;
  esac

  if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git branch -D "$branch" \
      || post_merge_fail "ローカルブランチを消せない: $branch" "git branch -D $branch をやり直すこと"
    say "  ok   ローカルブランチを削除した（$branch）"
  else
    say "  --   ローカルブランチは既に無い（$branch）"
  fi

  next "#$N をマージし、worktree とブランチを片付けた（PR #$PR）。"
}

# ══════════════════════════════════════════════════════════════════
case "$SUB" in
  only)  do_commit 0 "$@";;
  push)  do_commit 1 "$@";;
  merge) do_merge "$@";;
  *) die "未知のサブコマンド: $SUB
使い方: bash scripts/flow/commit.sh <only|push|merge> ...";;
esac
