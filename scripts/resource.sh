#!/usr/bin/env bash
# ============================================================
# Shared Resource Manager — worktree / devcontainer 間の排他制御
# [Template] research-project-template 由来
# ============================================================
#
# 複数 worktree・複数 devcontainer が外部リソース（ポート、GPU、ROS master 等）を
# 奪い合う問題への対処（#52）。flock ベースの薄いラッパ:
#
#   - リソース自身に聞く: レジストリ DB や daemon を持たない
#   - flock で統一ライフサイクル: プロセスが死ねば OS が自動解放（ゾンビロック無し）
#   - bind mount で同じロックファイルを見れば、コンテナ境界を超えて排他が効く
#
# Usage:
#   bash scripts/resource.sh acquire <name> [--wait|--timeout N] -- <cmd...>
#   bash scripts/resource.sh status  [name]
#   bash scripts/resource.sh release <name>
#   bash scripts/resource.sh list
#
# コマンド:
#   acquire  ロックを取ってコマンドを実行する。取れなければ既定で即エラー
#            （--wait は無期限待ち、--timeout N は N 秒待ち）。
#            コマンドの終了・プロセスの死で OS がロックを自動解放する
#   status   flock の非破壊プローブで FREE / BUSY を判定し、holder を表示する
#   release  holder の pid を読み、同一ホストなら SIGTERM を送る（→自動解放）。
#            別ホスト/コンテナの holder には手順を案内する
#   list     definitions.json のリソース定義を表示する
#
# ロックディレクトリ（優先順）:
#   1. $RESOURCE_LOCK_DIR
#   2. /var/resource-registry           … bind mount 済みなら複数コンテナ間で共有
#   3. <repo>/data/shared/resources/locks … 既定。worktree 間で共有
#
# リソース定義（任意。無くても ad-hoc な名前で動作する）:
#   data/shared/resources/definitions.json
#   例: { "review_server": {"type": "port", "port": 5051},
#         "gpu:0": {"type": "device"} }
#
# 制約:
#   - NFS 上では flock の動作が保証されない。ロックはローカルディスクに置くこと
#   - macOS ホストに flock(1) が無い場合は python3 (fcntl) にフォールバックする
#
# Exit codes:
#   0 正常 / 1 引数・環境エラー / 10 リソース BUSY（acquire 失敗）
#   acquire 成功時はラップしたコマンドの exit code をそのまま返す

set -uo pipefail

err()  { echo "[resource] $*" >&2; }

# --- ロックディレクトリの解決 -------------------------------------------
resolve_lock_dir() {
  if [ -n "${RESOURCE_LOCK_DIR:-}" ]; then
    echo "$RESOURCE_LOCK_DIR"
  elif [ -d /var/resource-registry ]; then
    echo /var/resource-registry
  else
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
      err "git リポジトリ外です。RESOURCE_LOCK_DIR を指定してください"; exit 1; }
    # worktree の場合は main リポジトリ側の data/shared を使う（共有のため）
    local common
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [ -n "$common" ] && root=$(dirname "$common")
    echo "$root/data/shared/resources/locks"
  fi
}

DEFS_FILE_REL="data/shared/resources/definitions.json"

resolve_defs_file() {
  local root common
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] && root=$(dirname "$common")
  echo "$root/$DEFS_FILE_REL"
}

# name をファイル名として安全にする（gpu:0 → gpu%3A0 のような変換はせず / と .. のみ拒否）
sanitize() {
  case "$1" in
    ""|*/*|*..*) err "不正なリソース名: '$1'"; exit 1 ;;
  esac
  echo "${1//:/__}"
}

have_flock() { command -v flock >/dev/null 2>&1; }

# --- flock 実行（flock(1) が無ければ python3 fcntl にフォールバック） ----
# lock_exec <lockfile> <mode> <meta-json> -- <cmd...>
#   mode: nonblock | wait | timeout:<N>
lock_exec() {
  local lockfile="$1" mode="$2" meta="$3"; shift 3
  [ "$1" = "--" ] && shift

  if have_flock; then
    local opts=(-n)
    case "$mode" in
      wait) opts=(-x) ;;
      timeout:*) opts=(--timeout "${mode#timeout:}") ;;
    esac
    # サブシェルが fd 9 でロックを保持したままメタデータを書き、コマンドを exec する
    # pid はロック保持プロセス自身（$BASHPID。exec 後も同じ pid）を書く
    (
      exec 9>>"$lockfile"
      flock "${opts[@]}" 9 || exit 10
      printf '%s\n' "${meta/__PID__/$BASHPID}" >"$lockfile"
      exec "$@"
    )
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    RESOURCE_META="$meta" python3 - "$lockfile" "$mode" "$@" <<'PYEOF'
import fcntl, os, sys, time
lockfile, mode, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
f = open(lockfile, "a+")
deadline = None
if mode.startswith("timeout:"):
    deadline = time.time() + float(mode.split(":", 1)[1])
while True:
    try:
        fcntl.flock(f, fcntl.LOCK_EX | (0 if mode == "wait" and deadline is None else fcntl.LOCK_NB))
        break
    except OSError:
        if mode == "nonblock" or (deadline and time.time() >= deadline):
            sys.exit(10)
        time.sleep(0.2)
f.truncate(0); f.seek(0)
# pid はロック保持プロセス自身（execvp 後も同じ pid）
f.write(os.environ.get("RESOURCE_META", "").replace("__PID__", str(os.getpid())) + "\n"); f.flush()
# PEP 446: fd は既定で非継承。継承可能にしないと execvp でロックが解放される
os.set_inheritable(f.fileno(), True)
os.execvp(cmd[0], cmd)  # fd はロックを保持したまま引き継がれる
PYEOF
    return $?
  fi

  err "flock も python3 も見つかりません"; exit 1
}

# lock_probe <lockfile> → 0: FREE / 10: BUSY
lock_probe() {
  local lockfile="$1"
  [ -e "$lockfile" ] || return 0
  if have_flock; then
    ( exec 9<"$lockfile"; flock -n -s 9 ) && return 0 || return 10
  fi
  python3 - "$lockfile" <<'PYEOF'
import fcntl, sys
try:
    f = open(sys.argv[1])
    fcntl.flock(f, fcntl.LOCK_SH | fcntl.LOCK_NB)
    sys.exit(0)
except OSError:
    sys.exit(10)
PYEOF
}

meta_json() {
  local name="$1"; shift
  local wt
  wt=$(git rev-parse --show-toplevel 2>/dev/null || echo "-")
  # pid はロック保持プロセスが書き込み時に __PID__ を自分の pid に置換する
  printf '{"resource":"%s","pid":__PID__,"host":"%s","worktree":"%s","started":"%s","cmd":"%s"}' \
    "$name" "$(hostname)" "$wt" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# メタデータ JSON は自分で書いた既知の1行形式なので、python3 に依存せず sed で読む
meta_get() {  # meta_get <lockfile> <key>  (pid は数値、他は文字列)
  local lockfile="$1" key="$2"
  if [ "$key" = "pid" ]; then
    sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$lockfile" | head -1
  else
    sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$lockfile" | head -1
  fi
}

show_meta() {
  local lockfile="$1" k v
  [ -s "$lockfile" ] || return 0
  for k in pid host worktree started cmd; do
    v=$(meta_get "$lockfile" "$k")
    [ -n "$v" ] && echo "    $k: $v"
  done
}

# --- コマンド ------------------------------------------------------------

cmd_acquire() {
  local name="" mode="nonblock"
  name="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait)    mode="wait"; shift ;;
      --timeout) mode="timeout:$2"; shift 2 ;;
      --)        shift; break ;;
      *) err "不明な引数: $1"; exit 1 ;;
    esac
  done
  [ $# -gt 0 ] || { err "実行するコマンドがありません（acquire <name> -- <cmd...>）"; exit 1; }

  local dir file
  dir=$(resolve_lock_dir); mkdir -p "$dir"
  file="$dir/$(sanitize "$name").lock"

  lock_exec "$file" "$mode" "$(meta_json "$name" "$*")" -- "$@"
  local rc=$?
  # rc=10 が「BUSY で取れなかった」のか「コマンド自身の exit 10」なのかをプローブで判別
  if [ $rc -eq 10 ] && ! lock_probe "$file"; then
    err "リソース '$name' は使用中です:"
    show_meta "$file" >&2
    err "待つ場合: acquire $name --wait -- <cmd>"
  fi
  return $rc
}

cmd_status() {
  local dir target="${1:-}"
  dir=$(resolve_lock_dir)
  [ -d "$dir" ] || { echo "（ロックなし: $dir が存在しません）"; return 0; }

  local found=false f name state
  for f in "$dir"/*.lock; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .lock); name="${name//__/:}"
    [ -n "$target" ] && [ "$name" != "$target" ] && continue
    found=true
    if lock_probe "$f"; then state="FREE"; else state="BUSY"; fi
    echo "$name: $state"
    [ "$state" = "BUSY" ] && show_meta "$f"
  done
  [ "$found" = true ] || echo "（該当するロックはありません）"
}

cmd_release() {
  local name="$1" dir file
  dir=$(resolve_lock_dir)
  file="$dir/$(sanitize "$name").lock"
  [ -e "$file" ] || { err "ロックファイルがありません: $name"; exit 1; }

  if lock_probe "$file"; then
    echo "リソース '$name' は既に FREE です"
    return 0
  fi

  local pid host
  pid=$(meta_get "$file" pid)
  host=$(meta_get "$file" host)
  if [ -z "${pid:-}" ]; then
    err "holder 情報を読めません。手動で確認してください: $file"; exit 1
  fi
  if [ "${host:-}" != "$(hostname)" ]; then
    # ${pid} と括るのは必須。bash 3.2 は `$pid）` の全角括弧の先頭バイトを
    # 変数名に含めてしまい、set -u 下で unbound variable になる（#122 で実測）
    err "holder は別ホスト/コンテナ（$host, pid=${pid}）です。そちらで kill してください:"
    err "  kill $pid   # on $host"
    exit 1
  fi
  echo "holder (pid=$pid) に SIGTERM を送ります"
  kill "$pid" 2>/dev/null || { err "kill に失敗（既に終了済み?）"; exit 1; }
}

cmd_list() {
  local defs
  defs=$(resolve_defs_file) || { err "git リポジトリ外です"; exit 1; }
  if [ ! -f "$defs" ]; then
    echo "定義ファイルなし: $defs"
    echo "（definitions.json は任意。acquire は ad-hoc な名前でも動作します）"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for name, spec in d.items():
    print(f\"{name}: {json.dumps(spec, ensure_ascii=False)}\")" "$defs"
  else
    cat "$defs"
  fi
}

usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  acquire) shift; [ $# -ge 1 ] || { err "リソース名がありません"; exit 1; }; cmd_acquire "$@" ;;
  status)  shift; cmd_status "${1:-}" ;;
  release) shift; [ $# -ge 1 ] || { err "リソース名がありません"; exit 1; }; cmd_release "$1" ;;
  list)    cmd_list ;;
  -h|--help|help|"") usage ;;
  *) err "不明なコマンド: $1"; usage >&2; exit 1 ;;
esac
