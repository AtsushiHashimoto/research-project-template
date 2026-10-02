#!/usr/bin/env bash
# worktree-relative.sh の回帰テスト（ネットワーク不要。一時リポジトリで数秒）
#   作った worktree の .git が相対パスであること・worktree 内で git status が動くこと・
#   リポジトリを別の場所に移しても（＝ホストと devcontainer でマウント先が違っても）動くこと・
#   git < 2.48 の経路で worktree が prunable にならないこと、を pin する。
# shellcheck disable=SC2015  # ok/ng は常に 0 を返すので A&&B||C で安全
set -uo pipefail
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok() { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng() { echo "FAIL $1"; FAIL=1; }
G=(git -c user.name=t -c user.email=t@t)

v=$(git --version | awk '{print $3}'); maj=${v%%.*}; r=${v#*.}; min=${r%%.*}
NATIVE=0; { [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 48 ]; }; } && NATIVE=1

run_case() {  # $1=ラベル $2=WORKTREE_RELATIVE_FORCE_LEGACY
  local L=$1 base="$TMP/$1" R wt
  mkdir -p "$base/a" && R="$base/a/repo"
  "${G[@]}" init -q -b main "$R" && "${G[@]}" -C "$R" commit -q --allow-empty -m init
  mkdir -p "$R/worktrees"
  ( cd "$R" && WORKTREE_RELATIVE_FORCE_LEGACY=$2 bash "$ROOT/scripts/worktree-relative.sh" add worktrees/issue1 -b feature/1-x >/dev/null 2>&1 ) \
    && ok "$L: add が成功" || { ng "$L: add が成功"; return; }
  wt="$R/worktrees/issue1"
  local line; line=$(cat "$wt/.git")
  [[ "$line" == "gitdir: ../"* ]] && ok "$L: worktree 側 .git が相対 ($line)" || ng "$L: worktree 側 .git が相対 ($line)"
  [ "$(git -C "$wt" branch --show-current)" = feature/1-x ] && ok "$L: ブランチが作られる" || ng "$L: ブランチが作られる"
  git -C "$wt" status >/dev/null 2>&1 && ok "$L: worktree で git status が動く" || ng "$L: worktree で git status が動く"
  ( cd "$R" && git worktree list --porcelain ) | grep -q '^prunable' \
    && ng "$L: prunable にならない" || ok "$L: prunable にならない"
  # マウント先が変わった状況: リポジトリごと別パスへ移す
  mv "$base/a" "$base/b"; wt="$base/b/repo/worktrees/issue1"
  git -C "$wt" status >/dev/null 2>&1 && ok "$L: 移動後も worktree で git status が動く" || ng "$L: 移動後も worktree で git status が動く"
  ( cd "$base/b/repo" && WORKTREE_RELATIVE_FORCE_LEGACY=$2 bash "$ROOT/scripts/worktree-relative.sh" fix >/dev/null 2>&1 ) \
    && ok "$L: fix が成功" || ng "$L: fix が成功"
  [[ "$(cat "$wt/.git")" == "gitdir: ../"* ]] && ok "$L: fix 後も worktree 側は相対" || ng "$L: fix 後も worktree 側は相対"
  ( cd "$base/b/repo" && git worktree list --porcelain ) | grep -q '^prunable' \
    && ng "$L: fix 後は移動先で prunable にならない" || ok "$L: fix 後は移動先で prunable にならない"
  git -C "$wt" status >/dev/null 2>&1 && ok "$L: fix 後も git status が動く" || ng "$L: fix 後も git status が動く"
}

run_case legacy 1
if [ "$NATIVE" = 1 ]; then run_case native 0
else [ "$QUIET" = 1 ] || echo "skip native: git $v は --relative-paths 未対応（2.48 以降で検査）"; fi

# fix: 旧来の絶対パスで作られた worktree を相対化できる
R="$TMP/old/repo"; "${G[@]}" init -q -b main "$R" && "${G[@]}" -C "$R" commit -q --allow-empty -m init
mkdir -p "$R/worktrees" && git -C "$R" worktree add -q "$R/worktrees/issue2" -b f2 2>/dev/null
( cd "$R" && WORKTREE_RELATIVE_FORCE_LEGACY=1 bash "$ROOT/scripts/worktree-relative.sh" fix >/dev/null 2>&1 )
[[ "$(cat "$R/worktrees/issue2/.git")" == "gitdir: ../"* ]] && ok "fix: 絶対パスの既存 worktree を相対化" || ng "fix: 絶対パスの既存 worktree を相対化"

# 引数なしは非 0
bash "$ROOT/scripts/worktree-relative.sh" >/dev/null 2>&1 && ng "引数なしは非 0" || ok "引数なしは非 0"

exit $FAIL
