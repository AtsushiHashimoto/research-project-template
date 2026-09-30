#!/usr/bin/env bash
# .devcontainer/install-claude-native.sh の回帰テスト（#151）
#
# ネットワーク無しで決定的に動かす。PATH の先頭にスタブ curl を置き、スタブが
# 「偽インストーラ」を書き出す。偽インストーラは一時 HOME の ~/.local/bin/claude に
# 指定した版を返す launcher を作る。実 HOME・実 ~/.local・/usr には触れない。
#
# 切り替え（環境変数。run_install の引数で渡す）:
#   FAKE_CURL=ok|fail            スタブ curl が成功するか
#   FAKE_INSTALLER=ok|fail|noop  偽インストーラの挙動（noop は何もせず成功）
#   FAKE_VERSION=X.Y.Z           偽インストーラが入れる版
#
# 偽インストーラは公式インストーラと同じく「自分が作っていない既存 launcher は上書きしない」
# （既存があれば何もせず成功を返す）。退避しないと再導入で直らない状況を再現するため。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/.devcontainer/install-claude-native.sh"

QUIET=0
case "${1:-}" in -q|--quiet) QUIET=1 ;; esac

PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); [ "$QUIET" -eq 1 ] || printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; [ -n "${RUN_OUT:-}" ] && printf '%s\n' "$RUN_OUT" | sed 's/^/       | /'; }
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/claude-native-XXXXXX")"
cleanup() { [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# スタブ
# ---------------------------------------------------------------------------
mkdir -p "$TMPROOT/bin"

# make_launcher <path> <mode> [version]
#   mode: ok（"<ver> (Claude Code)"）/ warn（1行目に警告）/ fail（非ゼロ終了）/ empty（空出力）
make_launcher() {
  local path=$1 mode=$2 ver=${3:-}
  mkdir -p "$(dirname "$path")"
  case "$mode" in
    ok)    printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$ver" > "$path" ;;
    warn)  printf '#!/usr/bin/env bash\necho "Warning: something odd" >&2\necho "%s (Claude Code)"\n' "$ver" > "$path" ;;
    fail)  printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 3\n' > "$path" ;;
    empty) printf '#!/usr/bin/env bash\nexit 0\n' > "$path" ;;
  esac
  chmod +x "$path"
}

# 偽インストーラの本体（スタブ curl が -o の先に書き出す）
cat > "$TMPROOT/fake-install.sh" <<'FAKE'
#!/usr/bin/env bash
# 偽インストーラ。$1 はチャネル
case "${FAKE_INSTALLER:-ok}" in
  fail) echo "fake installer: failing" >&2; exit 1 ;;
  noop) echo "fake installer: noop"; exit 0 ;;
esac
bin="$HOME/.local/bin/claude"
if [ -e "$bin" ] || [ -L "$bin" ]; then
  # 公式インストーラと同じく、自分が作っていない launcher は上書きしない
  echo "fake installer: existing launcher left untouched"
  exit 0
fi
mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "${FAKE_VERSION:?}" > "$bin"
chmod +x "$bin"
echo "fake installer: installed ${FAKE_VERSION} ($1)"
FAKE

cat > "$TMPROOT/bin/curl" <<STUB
#!/usr/bin/env bash
# スタブ curl。-o の先に偽インストーラを書き出す。FAKE_CURL=fail で失敗する
[ "\${FAKE_CURL:-ok}" = fail ] && { echo "curl: (7) stub failure" >&2; exit 7; }
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o) out=\$2; shift 2 ;; *) shift ;; esac
done
[ -n "\$out" ] || { echo "stub curl: -o required" >&2; exit 2; }
cp "$TMPROOT/fake-install.sh" "\$out"
STUB
chmod +x "$TMPROOT/bin/curl"

# ---------------------------------------------------------------------------
# 実行ヘルパ
# ---------------------------------------------------------------------------
H=""          # 現在のケースの一時 HOME
RUN_OUT=""
RUN_RC=0
N=0

new_home() {
  N=$((N + 1))
  H="$TMPROOT/home$N"
  mkdir -p "$H"
}

# run_install [VAR=value ...] — 一時 HOME でスクリプトを実行する
#   呼び出し元の CLAUDE_NATIVE_MIN_VERSION / FAKE_* は落とし、既定値を試験する
run_install() {
  RUN_OUT="$(env -u CLAUDE_NATIVE_MIN_VERSION -u FAKE_CURL -u FAKE_INSTALLER -u FAKE_VERSION \
    HOME="$H" TMPDIR="$H" PATH="$TMPROOT/bin:$PATH" FAKE_VERSION=2.1.284 "$@" \
    bash "$SCRIPT" 2>&1)"
  RUN_RC=$?
}

outhas() { case "$RUN_OUT" in *"$1"*) return 0 ;; esac; return 1; }
# 退避ファイル（claude.pre-install.<pid>）が残っているか
has_backup() {
  local f
  for f in "$H/.local/bin/claude.pre-install."*; do
    { [ -e "$f" ] || [ -L "$f" ]; } && return 0
  done
  return 1
}
bin_version() { "$H/.local/bin/claude" --version 2>/dev/null | head -n1; }

# ---------------------------------------------------------------------------
say "=== install-claude-native.sh self-test ==="
say "[version] 版比較のふち（既存 launcher の版で導入を省くか）"

# check_edge <既存の版> <期待: pass|fail>
#   fail 側は偽インストーラも同じ版しか入れない（版不足のまま）状況で FAIL (version: を確かめる
check_edge() {
  local ver=$1 expect=$2
  new_home
  make_launcher "$H/.local/bin/claude" ok "$ver"
  run_install FAKE_VERSION="$ver"
  if [ "$expect" = pass ]; then
    if [ "$RUN_RC" -eq 0 ] && outhas "skip (found" && outhas "ok ("; then
      ok "$ver は下限以上として PASS（導入を省く）"
    else
      ng "$ver が PASS しない (rc=$RUN_RC)"
    fi
  else
    if [ "$RUN_RC" -ne 0 ] && outhas "install (reason: found" && outhas "FAIL (version:"; then
      ok "$ver は下限未満として FAIL"
    else
      ng "$ver が FAIL しない (rc=$RUN_RC)"
    fi
  fi
}
check_edge 2.1.280 pass
check_edge 2.1.28 fail
check_edge 2.1.1000 pass
check_edge 2.1.280-beta pass

# 下限の上書き口はログに出る
new_home
make_launcher "$H/.local/bin/claude" ok 2.1.284
run_install CLAUDE_NATIVE_MIN_VERSION=9.9.9 FAKE_VERSION=2.1.284
if [ "$RUN_RC" -ne 0 ] && outhas "overridden by CLAUDE_NATIVE_MIN_VERSION=9.9.9" && outhas "FAIL (version:"; then
  ok "CLAUDE_NATIVE_MIN_VERSION の上書きが効き、ログに明示される"
else
  ng "CLAUDE_NATIVE_MIN_VERSION の上書きが効かないか、ログに出ない (rc=$RUN_RC)"
fi

say "[reinstall] 再導入の経路"

# 導入なし（初回）
new_home
run_install
if [ "$RUN_RC" -eq 0 ] && outhas "install (reason: missing" && [ "$(bin_version)" = "2.1.284 (Claude Code)" ]; then
  ok "launcher が無ければ導入して合格する"
else
  ng "初回導入が通らない (rc=$RUN_RC)"
fi

# 壊れたリンク
new_home
mkdir -p "$H/.local/bin"
ln -s "$H/no/such/versions/2.1.277" "$H/.local/bin/claude"
run_install
if [ "$RUN_RC" -eq 0 ] && [ ! -L "$H/.local/bin/claude" ] && [ "$(bin_version)" = "2.1.284 (Claude Code)" ]; then
  ok "壊れたリンク → 退避して再導入する"
else
  ng "壊れたリンクから直らない (rc=$RUN_RC)"
fi

# 2.1.277 → 再導入
new_home
make_launcher "$H/.local/bin/claude" ok 2.1.277
run_install
if [ "$RUN_RC" -eq 0 ] && outhas "install (reason: found 2.1.277 < 2.1.280)" \
  && outhas "moved stale launcher aside" && outhas "ok (2.1.284 >= 2.1.280)"; then
  ok "2.1.277 → 退避して再導入し、下限以上で成功する"
else
  ng "2.1.277 から再導入できない (rc=$RUN_RC)"
fi
if has_backup; then
  ng "成功後に退避ファイルが残っている"
else
  ok "成功後は退避ファイルを消す"
fi

# --version が非ゼロ／空出力 → 再導入
for mode in fail empty; do
  new_home
  make_launcher "$H/.local/bin/claude" "$mode"
  run_install
  if [ "$RUN_RC" -eq 0 ] && outhas "install (reason:" && [ "$(bin_version)" = "2.1.284 (Claude Code)" ]; then
    ok "--version が $mode（非ゼロ/空出力）→ 再導入する"
  else
    ng "--version が $mode のとき再導入しない (rc=$RUN_RC)"
  fi
done

# 1 行目に警告
new_home
make_launcher "$H/.local/bin/claude" warn 2.1.284
run_install
if [ "$RUN_RC" -eq 0 ] && outhas "skip (found 2.1.284)"; then
  ok "--version の 1 行目に警告が出ても版を取り出せる"
else
  ng "警告行があると版を取り出せない (rc=$RUN_RC)"
fi

say "[failure] 失敗時の扱い"

# download 失敗 → 既存が残る
new_home
make_launcher "$H/.local/bin/claude" ok 2.1.277
run_install FAKE_CURL=fail
if [ "$RUN_RC" -ne 0 ] && outhas "FAIL (download:" \
  && [ "$(bin_version)" = "2.1.277 (Claude Code)" ] && ! outhas "moved stale launcher aside"; then
  ok "download 失敗 → 非ゼロ・FAIL (download:・既存 launcher に触らない"
else
  ng "download 失敗の扱いが違う (rc=$RUN_RC)"
fi

# installer 失敗 → 退避した launcher が戻る
new_home
make_launcher "$H/.local/bin/claude" ok 2.1.277
run_install FAKE_INSTALLER=fail
if [ "$RUN_RC" -ne 0 ] && outhas "FAIL (installer:" && outhas "restored $H/.local/bin/claude" \
  && [ "$(bin_version)" = "2.1.277 (Claude Code)" ]; then
  ok "installer 失敗 → 非ゼロ・FAIL (installer:・退避した launcher を戻す"
else
  ng "installer 失敗時に launcher が戻らない (rc=$RUN_RC)"
fi
if has_backup; then
  ng "復元後に退避ファイルが残っている"
else
  ok "復元後は退避ファイルが残らない"
fi

# installer 失敗（壊れたリンクの退避）→ リンクのまま戻る
new_home
mkdir -p "$H/.local/bin"
ln -s "$H/no/such/target" "$H/.local/bin/claude"
run_install FAKE_INSTALLER=fail
if [ "$RUN_RC" -ne 0 ] && [ -L "$H/.local/bin/claude" ] \
  && [ "$(readlink "$H/.local/bin/claude")" = "$H/no/such/target" ]; then
  ok "installer 失敗 → 壊れたリンクもリンクのまま戻す"
else
  ng "installer 失敗時に壊れたリンクが戻らない (rc=$RUN_RC)"
fi

# 版不足のまま（偽インストーラが古い版しか入れない）
new_home
run_install FAKE_VERSION=2.1.277
if [ "$RUN_RC" -ne 0 ] && outhas "FAIL (version: 2.1.277 < 2.1.280"; then
  ok "版不足のまま → 非ゼロ・FAIL (version:"
else
  ng "版不足を見逃した (rc=$RUN_RC)"
fi

# インストーラが成功を返したが launcher を作らない
new_home
run_install FAKE_INSTALLER=noop
if [ "$RUN_RC" -ne 0 ] && outhas "FAIL (version: missing"; then
  ok "インストーラが何もしない → 非ゼロ・FAIL (version: missing"
else
  ng "何もしないインストーラを見逃した (rc=$RUN_RC)"
fi

# 既存 launcher あり＋インストーラが成功を返したが launcher を作らない → 退避を戻す
new_home
make_launcher "$H/.local/bin/claude" ok 2.1.277
run_install FAKE_INSTALLER=noop
if [ "$RUN_RC" -ne 0 ] && outhas "FAIL (installer:" && outhas "restored $H/.local/bin/claude" \
  && [ "$(bin_version)" = "2.1.277 (Claude Code)" ]; then
  ok "既存 launcher＋何もしないインストーラ → 非ゼロ・FAIL (installer:・退避した launcher を戻す"
else
  ng "何もしないインストーラで既存 launcher を失った (rc=$RUN_RC)"
fi
if has_backup; then
  ng "復元後に退避ファイルが残っている（何もしないインストーラ）"
else
  ok "復元後は退避ファイルが残らない（何もしないインストーラ）"
fi

say
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
