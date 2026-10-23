#!/usr/bin/env bash
# safe-remove-worktree.sh と init-data.sh の共有ストアの扱い（一時リポジトリで数秒。ネットワーク不要）
#
#   - 共有ストアは main 基準で解決する（cwd 基準だと、worktree にリンクが無いとき退避したファイルが
#     worktree ごと消える）
#   - worktree-relative.sh add が lock した worktree も消せる。消せなかったときは lock し直す
#   - ストアが無ければ退避先なしで続け、ストアが symlink なら止める
#   - init-data.sh は symlink になったストアの上で「初期化しました」と言わない
set -uo pipefail

QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok() { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng() { echo "FAIL $1"; FAIL=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1（期待 '$3'・実際 '$2'）"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SAFE="$ROOT/scripts/safe-remove-worktree.sh"

# fixture <名前>: main（共有ストア付き）と、worktree-relative.sh add で作った worktree（lock 済み）
fixture() {
  M="$TMP/$1/main"; W="$M/worktrees/wt"; STORE="$M/data/shared"
  mkdir -p "$M/.claude" "$STORE"
  git -C "$M" init -q -b main
  echo '{"version":"1.1","shared_data_path":"data/shared","path_type":"relative"}' > "$M/.claude/worktree-config.json"
  printf 'data/\nworktrees/\n' > "$M/.gitignore"
  echo a > "$M/a.txt"
  git -C "$M" add .gitignore a.txt .claude/worktree-config.json && git -C "$M" commit -qm init
  echo marker > "$STORE/marker.txt"
  ( cd "$M" && bash "$ROOT/scripts/worktree-relative.sh" add worktrees/wt -b wt ) >/dev/null 2>&1
}
locked() { [ -e "$M/.git/worktrees/wt/locked" ] && echo yes || echo no; }
gone() { { [ -d "$W" ] || [ -d "$M/.git/worktrees/wt" ]; } && echo 残った || echo 消えた; }

# S1: worktree に data/shared のリンクが無いとき、退避したファイルは main の共有ストアに入る
fixture s1
check "（前提）add が lock した" "$(locked)" yes
mkdir -p "$W/data/local" && echo r > "$W/data/local/result.csv"
( cd "$W" && printf '1\ny\n' | bash "$SAFE" ) >"$TMP/s1.out" 2>&1; rc=$?
check "S1 終了コード 0" "$rc" 0
check "S1 lock した worktree を消す" "$(gone)" 消えた
check "S1 退避したファイルが main の共有ストアに残る" \
  "$([ -f "$STORE/backup_from_wt/result.csv" ] && echo yes || echo no)" yes
check "S1 共有ストアは無傷" "$(cat "$STORE/marker.txt" 2>/dev/null)" marker

# S2: remove が拒んだとき（変更がある）は lock し直して止まる
fixture s2
echo changed >> "$W/a.txt"
( cd "$M" && printf 'y\n' | bash "$SAFE" "$W" ) >"$TMP/s2.out" 2>&1; rc=$?
check "S2 remove が拒んだら非 0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
check "S2 worktree は残る" "$(gone)" 残った
check "S2 lock し直す（反対側の環境の prune から守り続ける）" "$(locked)" yes

# S3: 共有ストアがまだ無い（init-data.sh 未実行）なら、退避先なしで消せる
fixture s3
rm -rf "$STORE"
( cd "$M" && printf 'y\n' | bash "$SAFE" "$W" ) >"$TMP/s3.out" 2>&1; rc=$?
check "S3 終了コード 0" "$rc" 0
check "S3 worktree を消す" "$(gone)" 消えた

# S4: 共有ストアが symlink になっていたら何も消さずに止まる
fixture s4
mv "$STORE" "$TMP/s4/elsewhere" && ln -s "$TMP/s4/elsewhere" "$STORE"
( cd "$M" && printf 'y\n' | bash "$SAFE" "$W" ) >"$TMP/s4.out" 2>&1; rc=$?
check "S4 非 0 で止まる" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
check "S4 worktree は残る" "$(gone)" 残った

# I1: init-data.sh は symlink になった共有ストアの上で成功を報告しない
fixture i1
mkdir -p "$M/scripts" && cp "$ROOT/scripts/init-data.sh" "$M/scripts/"
rm -f "$M/.claude/worktree-config.json"
mv "$STORE" "$TMP/i1/elsewhere" && ln -s "$TMP/i1/elsewhere" "$STORE"
( cd "$M" && bash scripts/init-data.sh </dev/null ) >"$TMP/i1.out" 2>&1; rc=$?
check "I1 非 0 で止まる" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
check "I1 symlink はそのまま（上に作らない）" "$([ -L "$STORE" ] && [ ! -e "$TMP/i1/elsewhere/datasets" ] && echo yes || echo no)" yes

[ "$FAIL" = 0 ] && { [ "$QUIET" = 1 ] || echo "all passed"; exit 0; } || exit 1
