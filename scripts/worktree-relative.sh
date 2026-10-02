#!/usr/bin/env bash
# ============================================================
# worktree を「ホストと devcontainer の両方から git / gh が動く」形で作る・直す
# [Template] research-project-template 由来
# ============================================================
#
# 使い方:
#   bash scripts/worktree-relative.sh add <path> [git worktree add の残りの引数...]
#       例: bash scripts/worktree-relative.sh add worktrees/issue12 -b feature/12-x
#   bash scripts/worktree-relative.sh fix [<worktree のパス>...]
#       既存 worktree を直す。省略時は <リポジトリ>/worktrees/*/ のうち .git ファイルを持つもの
#
# git のバージョン分岐はこのスクリプトだけに置く（規則・スキルはここを呼ぶ）。
#
#   git >= 2.48: git worktree add --relative-paths（両側が相対パスになる）
#                fix は git worktree repair --relative-paths
#   git <  2.48: --relative-paths が無いので、作成後に **worktree 側の .git ファイルだけ**を
#                相対パスに書き換え、メイン側 .git/worktrees/<id>/gitdir は絶対パスのまま残す。
#                fix は worktree 側を相対化してから `git worktree repair <path>` でメイン側を
#                「実行した環境の絶対パス」に直す。
#
# メイン側を相対にしない理由（git 2.43 で確認）:
#   git < 2.48 は gitdir ファイルの相対パスを「カレントディレクトリ基準」で解決するため、
#   worktree が prunable と表示され、`git worktree prune`（および gc）が worktree の管理情報を
#   削除する。worktree 内で git / gh を動かすのに必要なのは worktree 側の .git だけで、
#   メイン側の gitdir は一覧・prune 用。別環境では `fix` を 1 回実行すればメイン側が直る。
#
# テスト用: WORKTREE_RELATIVE_FORCE_LEGACY=1 で git >= 2.48 でも旧版の経路を通す。

set -euo pipefail

die() { echo "[worktree-relative] ERROR: $*" >&2; exit 1; }
log() { echo "[worktree-relative] $*"; }

git_supports_relative() {
  [ "${WORKTREE_RELATIVE_FORCE_LEGACY:-0}" = 1 ] && return 1
  local v major rest minor
  v=$(git --version | awk '{print $3}')
  major=${v%%.*}; rest=${v#*.}; minor=${rest%%.*}
  [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 48 ]; }
}

# relpath <target> <base>: base ディレクトリから target への相対パス（どちらも物理絶対パス）
relpath() {
  local target=$1 base=$2 up=""
  while [ "${target#"$base"/}" = "$target" ] && [ "$target" != "$base" ]; do
    base=$(dirname "$base"); up="../$up"
    [ "$base" = / ] && { echo "${up}${target#/}"; return; }
  done
  if [ "$target" = "$base" ]; then up=${up%/}; echo "${up:-.}"; else echo "${up}${target#"$base"/}"; fi
}

# worktree 側の .git ファイルを相対パスにする（git < 2.48 用）
relativize_worktree_side() {
  local wt admin rel
  wt=$(cd "$1" && pwd -P)
  [ -f "$wt/.git" ] || die "$wt/.git がファイルではありません（linked worktree ではない）"
  admin=$(git -C "$wt" rev-parse --absolute-git-dir) || die "$wt の gitdir を解決できません（先に git worktree repair <path> を実行）"
  admin=$(cd "$admin" && pwd -P)
  rel=$(relpath "$admin" "$wt")
  printf 'gitdir: %s\n' "$rel" > "$wt/.git"
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || die "相対化後に $wt で git が動きません"
  log "相対化: $wt/.git -> gitdir: $rel"
}

cmd_add() {
  [ $# -ge 1 ] || die "使い方: $0 add <path> [git worktree add の引数...]"
  local path=$1; shift
  if git_supports_relative; then
    git worktree add --relative-paths "$path" "$@"
  else
    git worktree add "$path" "$@"
    relativize_worktree_side "$path"
  fi
}

cmd_fix() {
  local top paths=()
  top=$(git rev-parse --show-toplevel)
  if [ $# -gt 0 ]; then paths=("$@"); else
    local d
    for d in "$top"/worktrees/*/; do [ -f "$d.git" ] && paths+=("${d%/}"); done
  fi
  [ ${#paths[@]} -gt 0 ] || { log "対象の worktree がありません"; return 0; }
  local p
  if git_supports_relative; then
    git worktree repair --relative-paths "${paths[@]}"
  else
    for p in "${paths[@]}"; do
      # 別環境の絶対パスで壊れている場合に備え、先に repair で worktree 側を解決可能にする
      git worktree repair "$p" >/dev/null 2>&1 || true
      relativize_worktree_side "$p"
      git worktree repair "$p" >/dev/null 2>&1 || true   # メイン側 gitdir をこの環境の絶対パスに
    done
  fi
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  fix) shift; cmd_fix "$@" ;;
  *) die "使い方: $0 add <path> [args...] | fix [<path>...]" ;;
esac
