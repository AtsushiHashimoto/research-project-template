#!/usr/bin/env bash
# quality-check.sh の検査範囲に関する回帰テスト（#142 / #153）
#
# ツリー全体を検査すると、そのファイルを1行も触っていない PR が既存の指摘で落ちる。
# #105 が changed-file 判定から取り除いたのと同じ誤検出なので、ファイル単位の検査は
# base ref との差分に限定する。ここではその不変条件を静的に pin する
# （gate 自体は uv sync 等で重いので、実行せずスクリプトの構造を検査する）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
GATE="scripts/quality-check.sh"
PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }

echo "=== quality-check scope self-test ==="

# 1) shellcheck が全件走査に戻っていないこと
if grep -q "git ls-files '\*\.sh'" "$GATE"; then
  ng "shellcheck が git ls-files で全件走査している（#142 の回帰）"
else
  ok "shellcheck は全件走査していない"
fi

# 2) 変更ファイル由来の集合を使っていること
if grep -q 'changed_of sh' "$GATE"; then
  ok "shellcheck は changed_of で変更ファイルに限定されている"
else
  ng "changed_of による限定が無い"
fi

# 3) base ref の解決とフォールバック順序があること
# shellcheck disable=SC2016  # these are grep patterns; $ must stay literal
if grep -q 'resolve_base_ref' "$GATE" && grep -q 'origin/\$default_branch' "$GATE"; then
  ok "base ref を origin -> ローカルの順で解決する"
else
  ng "base ref の解決処理が見当たらない"
fi

# 4) 「検査が走らなかった」を PASS に畳まないこと
if grep -q 'base ref を解決できず' "$GATE" && \
   awk '/base ref を解決できず/{found=1} found && /FAILED=1/{ok=1} END{exit !ok}' "$GATE"; then
  ok "base ref 解決不能を FAILED にする（PASS に畳まない）"
else
  ng "base ref 解決不能が握り潰されている"
fi

# 5) sourced lib を追う設定（単体検査では SC1091 が必ず出るため必須）
if grep -q -- '--source-path=SCRIPTDIR' "$GATE"; then
  ok "shellcheck -x --source-path=SCRIPTDIR を使っている"
else
  ng "sourced lib の解決設定が無い（SC1091 で落ちる）"
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
