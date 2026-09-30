#!/usr/bin/env bash
# commit-merge.sh の merge 前チェックの回帰テスト
#   偽の gh（呼ばれたら記録）とローカル bare remote で動く。ネットワーク不要。
#   pin する性質: worktree の中身が PR に全て入っていないときは gh pr merge を呼ばずに止まり、
#   worktree とブランチを残す。クリーンなら merge して後始末まで完走する。
# shellcheck disable=SC2015,SC2016  # ok/ng は常に 0 を返すので A&&B||C で安全 / 準備コマンドは eval で展開する
set -uo pipefail
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd); S="$ROOT/scripts/commit-merge.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok() { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng() { echo "FAIL $1"; FAIL=1; }
# 利用者の git 設定（hook・pull 設定など）から切り離す。commit-merge.sh 内の git にも効かせるため環境変数で渡す
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
G=(git -c init.defaultBranch=main)

mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\nexit 0\n' "$TMP" > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

# run_case <名前> <期待 rc> <期待 gh 呼び出し(0/1)> <worktree 残存(yes/no)> <出力に含む文言> <準備コマンド（wt 内で実行）> [第2引数]
run_case() {
  local name=$1 want_rc=$2 want_gh=$3 want_wt=$4 want_msg=$5 prep=$6 arg=${7:-../wt}
  local d="$TMP/$name"; mkdir -p "$d"; rm -f "$TMP/gh.log"
  (
    cd "$d" && "${G[@]}" init -q --bare origin.git && "${G[@]}" clone -q origin.git repo 2>/dev/null \
      && cd repo && "${G[@]}" checkout -q -b main && echo a > a && "${G[@]}" add a \
      && "${G[@]}" commit -qm init && "${G[@]}" push -q origin main 2>/dev/null \
      && "${G[@]}" branch -q --set-upstream-to=origin/main && "${G[@]}" branch -q feat \
      && "${G[@]}" worktree add -q ../wt feat && cd ../wt && eval "$prep"
  ) >"$d/prep.log" 2>&1 || { ng "$name: 準備に失敗"; sed 's/^/     /' "$d/prep.log"; return; }
  (cd "$d/repo" && PATH="$TMP/bin:$PATH" bash "$S" 1 "$arg") >"$d/out" 2>&1; local rc=$?
  local gh=0; [ -f "$TMP/gh.log" ] && gh=1
  if [ "$want_gh" = 1 ]; then  # merge したなら、正しい引数で呼び、ブランチを両側から消していること
    grep -qx "pr merge 1 --squash" "$TMP/gh.log" || { ng "$name: gh pr merge 1 --squash が呼ばれていない"; }
    [ -z "$(git -C "$d/repo" branch --list feat)" ] || ng "$name: ローカルブランチが残っている"
    [ -z "$(git -C "$d/origin.git" branch --list feat)" ] || ng "$name: リモートブランチが残っている"
  fi
  local wt=no; [ -d "$d/wt" ] && wt=yes
  if [ "$rc" = "$want_rc" ] && [ "$gh" = "$want_gh" ] && [ "$wt" = "$want_wt" ] && grep -qF -- "$want_msg" "$d/out"; then ok "$name"
  else ng "$name (rc=$rc gh=$gh wt=$wt; 期待 rc=$want_rc gh=$want_gh wt=$want_wt 文言=$want_msg)"; sed 's/^/     /' "$d/out"; fi
}

PUSH='"${G[@]}" push -q origin feat'
run_case "未追跡ファイルがあれば止まる"   1 0 yes "未コミットの変更" "$PUSH && echo x > d.csv"
run_case "未 push の commit があれば止まる" 1 0 yes "未 push の commit" "$PUSH && echo y > b && \"\${G[@]}\" add b && \"\${G[@]}\" commit -qm c"
run_case "一度も push していなければ止まる" 1 0 yes "比較できません" ":"
run_case "detached HEAD なら止まる"      1 0 yes "detached HEAD" "$PUSH && \"\${G[@]}\" checkout -q --detach"
run_case "存在しない worktree なら止まる" 1 0 yes "worktree がありません" "$PUSH" "../nonexistent"
run_case "クリーンなら merge して後始末（パスに空白）" 0 1 no "クリーンアップ完了" "$PUSH"

[ $FAIL = 0 ] && { [ "$QUIET" = 1 ] || echo "all passed"; exit 0; } || exit 1
