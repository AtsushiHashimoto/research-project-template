#!/usr/bin/env bash
# worktree-relative.sh / configure-worktree-paths.sh の回帰テスト（ネットワーク不要。一時リポジトリで数秒）
#   作った worktree の .git が相対パスであること・worktree 内で git status が動くこと・
#   リポジトリを別の場所に移しても（＝ホストと devcontainer でマウント先が違っても）動くこと・
#   prunable にならないこと・古い git が開けなくなる extensions.relativeWorktrees を書かないこと、を pin する。
# shellcheck disable=SC2015  # ok/ng は常に 0 を返すので A&&B||C で安全
set -uo pipefail
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok() { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng() { echo "FAIL $1"; FAIL=1; }
G=(git -c user.name=t -c user.email=t@t)
WR="$ROOT/scripts/worktree-relative.sh"
newrepo() { "${G[@]}" init -q -b main "$1" && "${G[@]}" -C "$1" commit -q --allow-empty -m init && mkdir -p "$1/worktrees"; }
relative() { [[ "$(cat "$1/.git")" == "gitdir: ../"* ]]; }
prunable() { git -C "$1" worktree list --porcelain | grep -q '^prunable'; }

# 1: add（パスに空白を含む）
B="$TMP/mount a"; R="$B/repo"; newrepo "$R"
( cd "$R" && bash "$WR" add worktrees/issue1 -b feature/1-x >/dev/null 2>&1 ) && ok "add が成功" || ng "add が成功"
W="$R/worktrees/issue1"
relative "$W" && ok "worktree 側 .git が相対 ($(cat "$W/.git"))" || ng "worktree 側 .git が相対 ($(cat "$W/.git"))"
[ "$(git -C "$W" branch --show-current)" = feature/1-x ] && ok "ブランチが作られる" || ng "ブランチが作られる"
git -C "$W" status >/dev/null 2>&1 && ok "worktree で git status が動く" || ng "worktree で git status が動く"
prunable "$R" && ng "prunable にならない" || ok "prunable にならない"
[ -z "$(git -C "$R" config --get extensions.relativeWorktrees)" ] && ok "extensions.relativeWorktrees を書かない" \
  || ng "extensions.relativeWorktrees を書かない"

# 2: マウント先が変わった状況（リポジトリごと別パスへ移す）→ worktree 内はそのまま動き、fix で一覧も直る
mv "$B" "$TMP/mount b"; R="$TMP/mount b/repo"; W="$R/worktrees/issue1"
git -C "$W" status >/dev/null 2>&1 && ok "移動後も worktree で git status が動く" || ng "移動後も worktree で git status が動く"
prunable "$R" && ok "（対照）移動直後はメイン側が prunable" || ng "（対照）移動直後はメイン側が prunable"
( cd "$W" && bash "$WR" fix >/dev/null 2>&1 ) && ok "worktree の中から fix しても成功" || ng "worktree の中から fix しても成功"
relative "$W" && ok "fix 後も worktree 側は相対" || ng "fix 後も worktree 側は相対"
prunable "$R" && ng "fix 後は移動先で prunable にならない" || ok "fix 後は移動先で prunable にならない"
git -C "$W" status >/dev/null 2>&1 && ok "fix 後も git status が動く" || ng "fix 後も git status が動く"

# 3: 旧来の絶対パスの worktree を configure-worktree-paths.sh 経由で相対化し、useRelativePaths を解除する
R="$TMP/old/repo"; newrepo "$R"; mkdir -p "$R/scripts"
cp "$ROOT/scripts/configure-worktree-paths.sh" "$WR" "$R/scripts/"
git -C "$R" worktree add -q "$R/worktrees/issue2" -b f2 2>/dev/null
git -C "$R" config worktree.useRelativePaths true
( cd "$R" && bash scripts/configure-worktree-paths.sh >/dev/null 2>&1 )
relative "$R/worktrees/issue2" && ok "configure: 絶対パスの既存 worktree を相対化" || ng "configure: 絶対パスの既存 worktree を相対化"
[ -z "$(git -C "$R" config --get worktree.useRelativePaths)" ] && ok "configure: useRelativePaths を解除" || ng "configure: useRelativePaths を解除"

# 4: fix は壊れたパスがあっても残りを処理し、非 0 で返す
R="$TMP/part/repo"; newrepo "$R"; git -C "$R" worktree add -q "$R/worktrees/issue3" -b f3 2>/dev/null
( cd "$R" && bash "$WR" fix "$R/nope" "$R/worktrees/issue3" >/dev/null 2>&1 ); rc=$?
[ $rc != 0 ] && ok "fix: 失敗があれば非 0" || ng "fix: 失敗があれば非 0"
relative "$R/worktrees/issue3" && ok "fix: 失敗の後のパスも処理する" || ng "fix: 失敗の後のパスも処理する"

# 5: 引数なしは非 0
bash "$WR" >/dev/null 2>&1 && ng "引数なしは非 0" || ok "引数なしは非 0"

exit $FAIL
