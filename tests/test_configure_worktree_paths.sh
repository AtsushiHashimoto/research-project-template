#!/usr/bin/env bash
# scripts/configure-worktree-paths.sh のゲート分岐を固定する回帰テスト
# 由来: 派生プロジェクト delta-clip-dev #167
#
# 守りたい不変条件:
#   1. 要件（両環境 git 2.48 以降 + opt-in）を満たさない限り
#      worktree.useRelativePaths を書かない
#   2. 相対パス化が有効でない限り git worktree repair を実行しない
#      （ホスト側とコンテナ側の双方から実行すると互いの参照を壊し合う）
#   3. 旧版が opt-in 無しで書いた useRelativePaths=true は勝手に外さない（退行させない）
#   4. 自分が未対応なのに設定が有効な「混在状態」を検出して警告する
#
# 実 git のバージョンは変えられないので、PATH の先頭に `git --version` だけを
# 偽装するシムを置いて分岐を走らせる。**シムは --version 以外を実 git に委譲する**ので、
# 検証できるのは「ゲートの分岐」であって「相対パスで実際に書かれるか」ではない。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/configure-worktree-paths.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "SKIP: $SCRIPT が無い"
  exit 0
fi

WORK=$(mktemp -d) || { echo "FAIL: 一時ディレクトリを作れない"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

REAL_GIT=$(command -v git) || { echo "SKIP: git が無い"; exit 0; }

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ng() {
  echo "FAIL: $1"
  [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
  fail=$((fail + 1))
}

# make_shim <dir> <偽装するバージョン>
make_shim() {
  mkdir -p "$1"
  cat >"$1/git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
  echo "git version $2"
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
  chmod +x "$1/git"
}

# run_case <名前> <偽装バージョン> <事前 config の並び…（key=value）>
#   出力を stdout+stderr でまとめて CASE_OUT に、実行後の設定値を CASE_REL に入れる
run_case() {
  local name="$1" version="$2"
  shift 2
  CASE_DIR="$WORK/$name"
  mkdir -p "$CASE_DIR"
  ( cd "$CASE_DIR" && "$REAL_GIT" init -q . ) || return 1
  local kv
  for kv in "$@"; do
    ( cd "$CASE_DIR" && "$REAL_GIT" config "${kv%%=*}" "${kv#*=}" )
  done
  make_shim "$WORK/shim-$name" "$version"
  CASE_OUT=$(cd "$CASE_DIR" && PATH="$WORK/shim-$name:$PATH" bash "$SCRIPT" 2>&1)
  CASE_REL=$(cd "$CASE_DIR" && "$REAL_GIT" config --bool --get worktree.useRelativePaths 2>/dev/null || echo unset)
}

# --- 1. 未対応 git・設定なし: 何も書かない -------------------------------------
run_case old-clean 2.43.0
if [ "$CASE_REL" = "unset" ]; then
  ok "git 2.43: useRelativePaths を書かない"
else
  ng "git 2.43 なのに useRelativePaths=$CASE_REL が書かれた" "$CASE_OUT"
fi

# --- 2. 対応 git・opt-in なし: 書かない（★ 本テストの核心） --------------------
run_case new-no-optin 2.50.0
if [ "$CASE_REL" = "unset" ]; then
  ok "git 2.50 / opt-in なし: useRelativePaths を書かない"
else
  ng "opt-in なしで useRelativePaths=$CASE_REL が書かれた" "$CASE_OUT"
fi
case "$CASE_OUT" in
  *relativePathsOptIn*) ok "opt-in の案内を表示する" ;;
  *) ng "opt-in の案内が出ていない" "$CASE_OUT" ;;
esac

# --- 3. 対応 git・opt-in あり: 書く -------------------------------------------
run_case new-optin 2.50.0 worktree.relativePathsOptIn=true
if [ "$CASE_REL" = "true" ]; then
  ok "git 2.50 / opt-in あり: useRelativePaths を有効化する"
else
  ng "opt-in ありなのに有効化されない（値=$CASE_REL）" "$CASE_OUT"
fi

# --- 4. opt-in が git の真値表記（1）でも効く ---------------------------------
run_case new-optin-bool 2.50.0 worktree.relativePathsOptIn=1
if [ "$CASE_REL" = "true" ]; then
  ok "opt-in=1（git の真値）を真として扱う"
else
  ng "opt-in=1 が無視された（値=$CASE_REL）" "$CASE_OUT"
fi

# --- 5. 旧版が書いた設定を勝手に外さない（退行防止） --------------------------
run_case new-legacy 2.50.0 worktree.useRelativePaths=true
if [ "$CASE_REL" = "true" ]; then
  ok "既存の useRelativePaths=true を維持する"
else
  ng "既存の useRelativePaths を外してしまった（値=$CASE_REL）" "$CASE_OUT"
fi
case "$CASE_OUT" in
  *WARNING*) ok "opt-in 無しで有効な状態を警告する" ;;
  *) ng "opt-in 無しで有効な状態を警告していない" "$CASE_OUT" ;;
esac

# --- 6. 混在状態（自分は未対応・設定は有効）を ERROR で知らせる ---------------
run_case old-mixed 2.43.0 worktree.useRelativePaths=true
case "$CASE_OUT" in
  *ERROR*prune*) ok "混在状態を ERROR で警告する" ;;
  *) ng "混在状態が警告されていない" "$CASE_OUT" ;;
esac

# --- 7. git リポジトリでなければスキップする ---------------------------------
mkdir -p "$WORK/not-a-repo"
out=$(cd "$WORK/not-a-repo" && bash "$SCRIPT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ "${out#*スキップ}" != "$out" ]; then
  ok "git リポジトリでなければスキップする"
else
  ng "非 git ディレクトリの扱いが想定と違う（rc=$rc）" "$out"
fi

# --- 8. 未対応 git が relativeWorktrees 拡張に当たったときの誤報防止 ----------
#   拡張が書かれると古い git は全コマンドが fatal になる。ここで
#   「git リポジトリではない」と誤報すると原因が見えなくなる。
run_case old-extension 2.43.0
printf '[extensions]\n\trelativeWorktrees = true\n' >>"$WORK/old-extension/.git/config"
"$REAL_GIT" -C "$WORK/old-extension" config core.repositoryformatversion 1 2>/dev/null
ext_out=$(cd "$WORK/old-extension" && PATH="$WORK/shim-old-extension:$PATH" bash "$SCRIPT" 2>&1)
if "$REAL_GIT" -C "$WORK/old-extension" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "SKIP: この環境の git は relativeWorktrees 拡張を受け付けるため 8 は検証不能"
else
  case "$ext_out" in
    *relativeWorktrees*) ok "拡張非対応を専用メッセージで報告する" ;;
    *"git リポジトリではない"*) ng "拡張非対応を『git リポジトリではない』と誤報した" "$ext_out" ;;
    *) ng "拡張非対応時のメッセージが想定と違う" "$ext_out" ;;
  esac
fi

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
