#!/usr/bin/env bash
# post-create.sh が「PATH 上で実際に起動する claude」の版を確かめることを固定する。
#
# install-claude-native.sh の検査は ~/.local/bin/claude の版しか見ない。PATH の先に古い claude
# （npm 版など）が居ると、「ok」と出たまま古い claude が起動する。post-create.sh の
# [post-create:claude-path] ブロックを切り出し、偽の claude を PATH に置いて判定を確かめる。
# ネットワーク・docker は不要。
set -uo pipefail

QUIET=0
case "${1:-}" in -q|--quiet) QUIET=1 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); [ "$QUIET" -eq 1 ] || printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  NG   %s\n' "$1" >&2; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1（期待 $3・実際 $2）"; fi; }
finish() { echo "=== $PASSED passed, $FAILED failed ==="; [ "$FAILED" -eq 0 ]; exit; }

POST_CREATE=.devcontainer/post-create.sh
INSTALLER=.devcontainer/install-claude-native.sh
START='# PATH 上で実際に起動する claude の版を確かめる'
END='# --- [Project]'

# ブロックを切り出す（見出しから [Project] マーカーの直前まで）
BLOCK=$(awk -v s="$START" -v e="$END" 'index($0, s) == 1 {f = 1} index($0, e) == 1 {f = 0} f' "$POST_CREATE")
if [ -z "$BLOCK" ]; then
  ng "post-create.sh に「$START」から始まるブロックが無い"
  finish
fi
ok "post-create.sh に claude-path ブロックがある"

# ブロックは installer の呼び出しより後にある（先に置くと、入れる前の版を見てしまう）
inst_line=$(grep -n 'bash .devcontainer/install-claude-native.sh; then' "$POST_CREATE" | cut -d: -f1 | sed -n '1p')
block_line=$(grep -nF "$START" "$POST_CREATE" | cut -d: -f1 | sed -n '1p')
if [ -n "$inst_line" ] && [ "$block_line" -gt "$inst_line" ]; then
  ok "ブロックは installer の呼び出し（$POST_CREATE:$inst_line）より後"
else
  ng "ブロック（行 ${block_line:-?}）が installer の呼び出し（行 ${inst_line:-?}）より後にない"
fi

# 下限を書き写していない（installer の MIN_VERSION_DEFAULT から読む）
min=$(awk -F= '/^MIN_VERSION_DEFAULT=[0-9.]+$/{print $2; exit}' "$INSTALLER")
if [ -z "$min" ]; then
  ng "$INSTALLER から MIN_VERSION_DEFAULT を読めない"
  finish
fi
expect "下限 $min を書き写していない" "$(grep -cF "$min" <<<"$BLOCK")" 0

# 偽の claude を PATH の先頭に置いてブロックを実行し、claude_fail を返す
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
run_block() {
  mkdir -p "$TMPD/bin"
  printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" > "$TMPD/bin/claude"
  chmod +x "$TMPD/bin/claude"
  (PATH="$TMPD/bin:$PATH"; claude_fail=0; eval "$BLOCK" >/dev/null 2>&1; echo "$claude_fail")
}
older=0.0.0   # 下限が x.y.0 でも常に下限未満（1 を引くと x.y.-1 になり読めない）
newer=$(awk -F. '{printf "%d.%d.%d", $1, $2, $3 + 1}' <<<"$min")

expect "下限未満（$older）で FAIL にする" "$(run_block "$older")" 1
expect "下限ちょうど（$min）は通す" "$(run_block "$min")" 0
expect "下限より新しい（$newer）は通す" "$(run_block "$newer")" 0

# PATH 上に claude が無いときも FAIL にする（/usr/bin に claude がある環境では確かめられない）
if [ -x /usr/bin/claude ] || [ -x /bin/claude ]; then
  ok "PATH 上に claude が無いときの確認は省略（/usr/bin に claude がある）"
else
  expect "PATH 上に claude が無いとき FAIL にする" \
    "$(PATH="/usr/bin:/bin"; claude_fail=0; eval "$BLOCK" >/dev/null 2>&1; echo "$claude_fail")" 1
fi

# 下限を読めない（installer の行の形が変わった）ときも FAIL にする
mkdir -p "$TMPD/repo/.devcontainer"
echo 'MIN_VERSION_DEFAULT="2.1.280"' > "$TMPD/repo/.devcontainer/install-claude-native.sh"
expect "下限を読めないとき FAIL にする" \
  "$(cd "$TMPD/repo" && PATH="$TMPD/bin:$PATH" && claude_fail=0 && eval "$BLOCK" >/dev/null 2>&1; echo "$claude_fail")" 1

finish
