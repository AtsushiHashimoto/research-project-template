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
#       既存 worktree を直す。省略時は <メインリポジトリ>/worktrees/*/ のうち .git ファイルを持つもの
#   bash scripts/worktree-relative.sh remove <path> [git worktree remove の引数...]
#       unlock してから remove する。remove が失敗したら lock し直す（登録を無防備に残さない）
#
# worktree の作成・修復・削除はこのスクリプトだけを通す（規則・スキルはここを呼ぶ）。
#
# 方式（git のバージョンによらず同じ）:
#   素の `git worktree add` で作り、直後に **worktree 側の .git ファイルだけ**を相対パスに書き換える。
#   メイン側 .git/worktrees/<id>/gitdir は「実行した環境の絶対パス」のまま残し、別環境では
#   `fix`（内部で `git worktree repair <path>`）でその環境の絶対パスに直す。
#
# git 2.48 の --relative-paths / worktree.useRelativePaths を使わない理由:
#   それらはリポジトリに extensions.relativeWorktrees を書き込み、git < 2.48 が同じリポジトリを
#   一切開けなくなる（ホストとコンテナで git のバージョンが違うと片側が全滅する）。
# メイン側 gitdir を相対にしない理由（git 2.43 で確認）:
#   git < 2.48 は相対の gitdir をカレントディレクトリ基準で解決し、worktree を prunable と判定する。
#   `git worktree prune`（および gc）が worktree の管理情報を削除する。
# add が worktree を lock する理由:
#   メイン側 gitdir は 1 つの環境でしか有効にならないので、反対側の環境で `git gc --auto`
#   （内部で `git worktree prune`）が走ると、その worktree の登録が消える。
#   lock した worktree は prune の対象外になる。消すときは `remove` サブコマンドを使う。
#   --reason は git 2.31 以上。それより古い git では理由なしで lock する。

set -euo pipefail

die()  { echo "[worktree-relative] ERROR: $*" >&2; exit 1; }
log()  { echo "[worktree-relative] $*"; }
warn() { echo "[worktree-relative] WARNING: $*" >&2; }

LOCK_REASON="ホストと devcontainer の両方から使う。消すときは git worktree unlock してから remove"

# relpath <target> <base>: base ディレクトリから target への相対パス（どちらも物理絶対パス）
relpath() {
  local target=$1 base=$2 up=""
  [ "$base" = / ] && { echo "${target#/}"; return; }
  while [ "${target#"$base"/}" = "$target" ] && [ "$target" != "$base" ]; do
    base=$(dirname "$base"); up="../$up"
    [ "$base" = / ] && { echo "${up}${target#/}"; return; }
  done
  if [ "$target" = "$base" ]; then up=${up%/}; echo "${up:-.}"; else echo "${up}${target#"$base"/}"; fi
}

# worktree 側の .git ファイルを相対パスにする。失敗は非 0 で返す（die しない）
relativize_worktree_side() {
  local wt admin rel
  wt=$(cd "$1" 2>/dev/null && pwd -P) || { warn "$1 がありません"; return 1; }
  [ -f "$wt/.git" ] || { warn "$wt/.git がファイルではありません（linked worktree ではない）"; return 1; }
  admin=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) \
    || { warn "$wt の gitdir を解決できません（登録が消えていないか git worktree list で確認。別環境で作ったならその環境で fix）"; return 1; }
  admin=$(cd "$admin" && pwd -P)
  rel=$(relpath "$admin" "$wt")
  printf 'gitdir: %s\n' "$rel" > "$wt/.git"
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || { warn "相対化後に $wt で git が動きません"; return 1; }
  log "相対化: $wt/.git -> gitdir: $rel"
}

cmd_add() {
  [ $# -ge 1 ] || die "使い方: $0 add <path> [git worktree add の引数...]"
  local path=$1; shift
  local lock=(--lock)
  [ "$(git worktree add -h 2>&1 | grep -c -- '--reason' || true)" -gt 0 ] && lock+=(--reason "$LOCK_REASON")
  # --lock で作成と同時に lock する（作成と lock の間に失敗して、lock の無い worktree が残らないように）
  git -c worktree.useRelativePaths=false worktree add "${lock[@]}" "$path" "$@" \
    || die "worktree を作れません: $path（フォルダを手で消して登録だけ残っている場合は
  git worktree unlock '$path' && git worktree prune を実行してからやり直す）"
  log "lock: $path（反対側の環境の prune で登録が消えないように。消すときは remove サブコマンドで）"
  relativize_worktree_side "$path" || die "作成した worktree の相対化に失敗しました: $path"
}

cmd_fix() {
  local main paths=() d p failed=0
  # worktree の中から呼ばれてもメインリポジトリを基準にする
  main=$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)
  if [ $# -gt 0 ]; then paths=("$@"); else
    for d in "$main"/worktrees/*/; do [ -f "$d.git" ] && paths+=("${d%/}"); done
  fi
  [ ${#paths[@]} -gt 0 ] || { log "対象の worktree がありません"; return 0; }
  for p in "${paths[@]}"; do
    # 別環境の絶対パスで壊れている場合に備え、先に repair で両側を解決可能にする
    git -C "$main" -c worktree.useRelativePaths=false worktree repair "$p" >/dev/null 2>&1 || true
    relativize_worktree_side "$p" || { failed=1; continue; }
  done
  return $failed
}

cmd_remove() {
  [ $# -ge 1 ] || die "使い方: $0 remove <path> [git worktree remove の引数...]"
  local path=$1 locked=0; shift
  # lock の無い古い worktree では unlock が失敗する。それは問題ない（locked=0 のまま）
  git worktree unlock "$path" 2>/dev/null && locked=1
  if git worktree remove "$@" "$path"; then return 0; fi
  if [ "$locked" = 1 ]; then
    git worktree lock --reason "$LOCK_REASON" "$path" 2>/dev/null || git worktree lock "$path" \
      || warn "$path を lock し直せませんでした（反対側の環境の prune で登録が消えうる）"
  fi
  return 1
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  fix) shift; cmd_fix "$@" ;;
  remove) shift; cmd_remove "$@" ;;
  *) die "使い方: $0 add <path> [args...] | fix [<path>...] | remove <path> [args...]" ;;
esac
