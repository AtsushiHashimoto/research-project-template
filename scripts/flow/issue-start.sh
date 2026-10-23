#!/usr/bin/env bash
#
# issue に着手する。**task 単位**のブランチと worktree に居ることを保証する（冪等）。
#
#   bash scripts/flow/issue-start.sh <issue番号>
#
# ブランチと worktree（.claude/rules/template/issue-hierarchy.md）:
#   親が task      → <prefix>/<TASK>-i<N>  worktrees/task<TASK>（同じ task の issue で共有）
#   親が task でない → <prefix>/<N>-<slug>   worktrees/issue<N>
#
# ★ 新規作成モード（--new）は持たない。非ゼロ終了の意味を
#   「着手の前提が揃っていない」1 通りに保つため。作成は issue-create.sh。

# shellcheck source=scripts/flow/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die "使い方: bash scripts/flow/issue-start.sh <issue番号>"
N="$1"

# ── 段 1. 種類ラベル ────────────────────────────────────────────
labels="$(issue_labels "$N")"
has_label "$labels" epic && die "#$N は epic である。epic / task は worktree を持たない（/epic-cycle を使う）"
has_label "$labels" task && die "#$N は task である。task は worktree を持たない（/task-run を使う）"
# ★ closed な issue に着手しない（worktree とコメントだけが増える）
[ "$(issue_state "$N")" = OPEN ] \
  || die "#$N は既に closed である。再開するなら gh issue reopen $N してから呼ぶこと"

kind="$(kind_of "$labels")"
[ -n "$kind" ] || die "#$N が種類ラベルを持たない（labels=$labels）。ラベルを付けること"
prefix="$(branch_prefix "$kind")"
[ -n "$prefix" ] || die "種類ラベル '$kind' に対応するブランチ接頭辞が無い（lib.sh の branch_prefix に足すこと。既定の接頭辞には丸めない）"

TITLE="$(issue_title "$N")"
head2 "#$N [$kind] $TITLE"

# ── 段 2. ブランチに使う番号（task 単位）──────────────────────────
TASK="$(task_of "$N")"
say "  ..   ブランチの番号: $TASK$([ "$TASK" = "$N" ] && printf '（親が task ではないので自分の番号）')"

# ── 段 3. 親 task の goal を出す（読むのはモデル）──────────────────
if [ "$TASK" != "$N" ]; then
  head2 "親 task #$TASK の goal（★ 書き換えない）"
  gh_json "#$TASK の本文取得" gh issue view "$TASK" --json title,body -q '.title + "\n\n" + .body'
fi

# ── 段 4. ブランチと worktree を保証する（ヘッダの表）──────────────
MAIN="$(main_repo)"
if [ "$TASK" != "$N" ]; then
  WT_REL="worktrees/task$TASK"; BRANCH="$prefix/$TASK-i$N"
else
  WT_REL="worktrees/issue$N"; BRANCH="$prefix/$N-$(slug_of "$TITLE" "$kind")"
fi
WT="$MAIN/$WT_REL"
created=0

cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ "$cur" =~ ^($BRANCH_TYPES)/$TASK- ]]; then
  # ★ <type> の一致は要求しない。ブランチは task 単位なので、spec 段が作った
  #   ブランチの上で feature 段を続けるのが正しい
  head2 "すでに task #$TASK のブランチに居る（$cur）"
  # ★ いま居る場所を作業場所として扱う（$WT と別パスのこともある）
  WT="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
  say "  ok   worktree もブランチも作らない（$WT）"
elif [ -d "$WT" ]; then
  wt_branch="$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ "$wt_branch" =~ ^($BRANCH_TYPES)/$TASK- ]]; then
    head2 "worktree は既にある（作らない）"
    say "  ok   $WT（$wt_branch）"
  else
    die "$WT が別のブランチ（$wt_branch）で存在する。
勝手に消さない。/worktree-safe-remove で確認してから削除すること"
  fi
else
  head2 "worktree を作る"
  # ★ **登録だけ残って実体が無い**場合を先に弾く（手で消された worktree）。
  #   そのまま add すると `fatal: ... is a missing but already registered worktree`
  # `grep -c` は全入力を読むので pipefail の禁止形ではない（`grep -q` / `head` を使わない）
  registered="$(git -C "$MAIN" worktree list --porcelain 2>/dev/null \
                 | grep -c "^worktree $WT\$" || true)"
  if [ "${registered:-0}" -gt 0 ]; then
    die "$WT は worktree として登録されているが実体が無い（手で消された）。
先に登録を片付けること（lock されていても消せる）: (cd $MAIN && bash scripts/worktree-relative.sh remove $WT --force)"
  fi
  # ★ **同じ task の別ブランチが既に在るなら作らない**（1 task = 1 ブランチ）。
  #   ディレクトリの有無だけで判定すると、worktree だけ消えた状態で 2 本目が生える
  existing="$(git -C "$MAIN" for-each-ref --format='%(refname:short)' "refs/heads/*/$TASK-*" \
               2>/dev/null || true)"
  reuse=""
  for b in $existing; do
    [[ "$b" =~ ^($BRANCH_TYPES)/$TASK- ]] && { reuse="$b"; break; }
  done
  # ★ `git worktree add` を直接呼ばない。worktree 側の .git を相対化する
  #   scripts/worktree-relative.sh を通す（`.claude/rules/template/git-workflow.md`。
  #   `--relative-paths` は使わない。git < 2.48 がリポジトリを開けなくなるため）
  WT_ADD="$MAIN/scripts/worktree-relative.sh"
  [ -f "$WT_ADD" ] || die "scripts/worktree-relative.sh が無い（worktree の作成はここを通す）"
  if [ -n "$reuse" ]; then
    # ★ 既存ブランチには -b を付けない（付けると `already exists` で落ちる）
    # ★ 着手コメントにも**実際に使った名前**を書く（新規名のままだと issue に嘘が残る）
    BRANCH="$reuse"
    say "  ..   task #$TASK のブランチが既にある（$reuse）。それを使う"
    (cd "$MAIN" && bash "$WT_ADD" add "$WT" "$reuse") || die "worktree の作成が失敗した"
  else
    (cd "$MAIN" && bash "$WT_ADD" add "$WT" -b "$BRANCH" "$(start_point)") \
      || die "worktree の作成が失敗した"
  fi
  created=1
  say "  ok   $WT"
  # ★ 生成リンク（スキル・ルール）とフックを worktree に整える。無いと worktree の中で
  #   エージェントがスキルを見つけられない
  bash "$MAIN/scripts/configure-agent-workflow.sh" "$WT" \
    || die "scripts/configure-agent-workflow.sh $WT が失敗した。直してから呼び直すこと"
fi

# ── 段 5. 共有データの symlink（★ **状態**で判定する）───────────────
# ★ `created` では判定しない。setup-worktree.sh が一度落ちると worktree は残るので、
#   再実行が「既にある」経路に入って**保護が永久に張られない**（/review で実測指摘）。
# ★ `-L` でも判定しない。**ダングリングな symlink でも `-L` は真**。
#   **何に解決するか**で見る（setup-worktree.sh の data/shared の分類と同じ。場所は shared-store.sh が単一情報源）
[ -f "$MAIN/scripts/lib/shared-store.sh" ] || die "scripts/lib/shared-store.sh が無い（共有ストアの場所はここが単一情報源）"
. "$MAIN/scripts/lib/shared-store.sh"
if ! store_rel="$(shared_store_path "$MAIN")"; then die "共有ストアの場所を解決できない（$MAIN/.claude/worktree-config.json）"; fi
# ★ 解決する**前**のパスで見る（ストア自体が symlink にすり替わった形を、解決後の比較は素通りする）
assert_store_intact "$store_rel" || die "共有ストアが壊れている（$store_rel）。scripts/lib/shared-store.sh の出力を見ること"
STORE="$(readlink -f "$store_rel" 2>/dev/null || true)"
[ -n "$STORE" ] || die "共有ストア $store_rel を解決できない"
reaches_store() { [ -d "$WT/data/shared" ] && [ "$(readlink -f "$WT/data/shared" 2>/dev/null || true)" = "$STORE" ]; }
if ! reaches_store; then
  head2 "共有データの symlink を張る（scripts/setup-worktree.sh）"
  # ★ これを飛ばすと data/shared が worktree ローカルになり、
  #   flow/commit.sh merge の `git worktree remove --force` で成果物が消える
  ( cd "$WT" && bash "$MAIN/scripts/setup-worktree.sh" ) \
    || die "scripts/setup-worktree.sh が失敗した（data/shared が共有ストアを指さない）。
直してから呼び直すこと。**張られないまま作業すると成果物が worktree 削除で消える**"
  # ★ 終了コードだけを信じない（張り直した結果が共有ストアに届いているかを見る）
  reaches_store || die "setup-worktree.sh の後も $WT/data/shared が共有ストア $STORE に解決しない（実際: $(readlink -f "$WT/data/shared" 2>/dev/null || echo '<dangling>')）"
  say "  ok   data/shared は共有ストアに解決する（$STORE）"
else
  say "  ok   data/shared は共有ストアに解決する（$STORE）"
fi

# ── 段 6. 着手コメント（★ 作った直後だけ。毎回付けると積み上がる）────
if [ "$created" = 1 ]; then
  gh issue comment "$N" --body "## 着手

- ブランチ: \`$BRANCH\`$([ "$TASK" != "$N" ] && printf '（**task #%s 単位**）' "$TASK")
- Worktree: \`$WT_REL\`" >/dev/null || die "gh issue comment が失敗した"
  say "  ok   着手コメントを #$N に付けた"
fi
# 状態ラベルは付けない（.claude/rules/template/labels.md「in-progress は使わない」）

# ── 段 7. 次にやること（★ 毎回出す）──────────────────────────────
cd_line="cd $WT"
[ "$created" = 1 ] || cd_line="cd $WT （まだそこに居ないなら）"

if [ "$kind" = spec ]; then
  next \
    "#$N は spec の段である。作業場所:" \
    "" \
    "  $cd_line" \
    "" \
    "  1. .spec/issues/$N-<題>.md を書く（1 行目の見出しに #$N）" \
    "  2. auto-reviewer に代理判断させ .spec/issues/$N-auto-decisions.md を書かせる" \
    "     モデルは bash scripts/resolve-model.sh abstract-review で解決する" \
    "  3. 停止条件に該当したら**進まずに報告する**"
fi

next \
  "#$N は $kind の段である。作業場所:" \
  "" \
  "  $cd_line" \
  "" \
  "  1. 実装・測定を行い、作業差分を作る" \
  "  2. 進捗を /issue-report で #$N に記録する" \
  "  3. 終わったら bash scripts/flow/issue-finish.sh $N $TASK"
