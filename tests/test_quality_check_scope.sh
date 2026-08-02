#!/usr/bin/env bash
# quality-check.sh の検査範囲に関する回帰テスト（#135。原案は PR #129）
#
# ツリー全体を検査すると「そのファイルを1行も触っていない変更」が既存の指摘で落ちる。
# ファイル単位で完結する検査（shellcheck / ruff）を変更ファイルに限定した不変条件と、
# #121 の成果（サマリ / warn_missing / bash 3.2 互換 / shebang 収集）が残っていることを pin する。
#
# ★ 原案（PR #129）から意図的に落とした項目:
#   - 「`git ls-files '*.sh'` が存在しないこと」の静的 grep
#     → 全件走査モードでは追跡ファイル一覧を正当に使うため誤 FAIL する。
#       代わりに **フィクスチャでの挙動**（限定されているか）を直接検査する。
#   - 「base ref 解決不能なら FAILED=1」
#     → 本仕様の Fallback（全件走査＋理由表示）と真っ向から衝突する。
#       全件走査は限定走査の上位集合なので検出漏れを生まず、
#       main が無いリポジトリで完了ゲートが恒久的に赤くなるのを避ける。
#       「フォールバックして理由を表示すること」を pin する形に書き換えた。
#   - 「shellcheck -x --source-path=SCRIPTDIR を使うこと」
#     → 現行実装（#121）は `-x` 無しで指摘0件を達成済み。
#       不要な要求を pin すると実装を縛るだけなので採用しない。
#
# 挙動テストは **スタブ shellcheck** を PATH に置いて行う。
# 検査したいのは「どのファイルが検査系に渡されるか」であってリンタの内容ではないため、
# 引数を記録し `QC_STUB_BAD` を含むファイルで落ちる疑似リンタで十分かつ決定的。
# 実物の shellcheck との結合は quality-check.sh の通常実行（完了ゲート）が担保する。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
GATE="scripts/quality-check.sh"

# -q / --quiet: 成功項目を出さない（quality-check.sh から呼ばれるときの騒音対策）。
# 失敗は常に出す。
QUIET=0
case "${1:-}" in -q|--quiet) QUIET=1 ;; esac

PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); [ "$QUIET" -eq 1 ] || printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/qc-scope-XXXXXX")"
cleanup() { [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"; }
trap cleanup EXIT

say "=== quality-check scope self-test ==="
say

# ---------------------------------------------------------------------------
# 静的 pin: #121 の成果と「限定しないもの」
# ---------------------------------------------------------------------------
say "[static] #121 の成果と限定範囲"

if grep -q 'append_ran' "$GATE" && grep -q '実行 (' "$GATE" && grep -q '未実行 (' "$GATE"; then
  ok "実行/失敗/未実行のサマリが残っている（#121 D4）"
else
  ng "サマリ機能が失われている（#121 の退行）"
fi

if grep -q 'warn_missing()' "$GATE" && grep -q 'warn_missing "shellcheck' "$GATE"; then
  ok "warn_missing が skip と分離されたまま残っている（#121 D2）"
else
  ng "warn_missing が失われている（#121 の退行）"
fi

# コメント行は除く（「mapfile は使わない」という注意書き自体に反応しないため）
if grep -vE '^[[:space:]]*#' "$GATE" \
  | grep -qE '(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|$)'; then
  ng "mapfile/readarray を使っている（macOS の bash 3.2 で動かない。#121 D1）"
else
  ok "bash 3.2 互換（mapfile/readarray 不使用）"
fi

if grep -q 'collect_sh_files' "$GATE" && grep -q 'ba)\?da\|(ba|da|k)?sh' "$GATE"; then
  ok "shebang 判定による対象収集が残っている（#121 D3）"
else
  ng "shebang 判定による対象収集が失われている（拡張子なしスクリプトが素通りする）"
fi

# mypy は限定しない（型エラーはファイル間を伝播する。#135 D3 警告1）
if grep -q 'uv run mypy src/' "$GATE" && ! grep -q 'mypy.*RUFF_TARGETS\|mypy.*CHANGED' "$GATE"; then
  ok "mypy は変更ファイルに限定されていない（#135 D3 警告1）"
else
  ng "mypy が変更ファイルに限定されている（型エラーの伝播を見逃す）"
fi

# 横断検査（MANIFEST / skill-refs / skill-labels）は限定しない
# 「プロジェクト固有の検査」節（横断検査の置き場）に範囲変数が現れないこと。
# 節の終わり（# 結果）以降のサマリ表示は範囲の告知なので対象外。
# ★ 見出しが改名されると f が立たず「空振り PASS」になる。見出しの存在自体も pin する
if ! grep -q '^# プロジェクト固有の検査$' "$GATE" || ! grep -q '^# 結果$' "$GATE"; then
  ng "節見出しが見つからない（この pin が空振りする。見出しを変えたらテストも直すこと）"
elif awk '/^# プロジェクト固有の検査$/{f=1} /^# 結果$/{f=0}
        f && /SCOPE_MODE|CHANGED_FILES/{bad=1} END{exit bad?1:0}' "$GATE"; then
  ok "横断検査（MANIFEST / スキル参照 / スキルラベル）は限定されていない"
else
  ng "横断検査が変更ファイルに限定されている（参照切れを検出できなくなる）"
fi

if grep -q 'QUALITY_FULL_SCAN' "$GATE" && grep -q 'QUALITY_BASE_BRANCH' "$GATE"; then
  ok "QUALITY_FULL_SCAN / QUALITY_BASE_BRANCH が定義されている"
else
  ng "全件走査への導線（QUALITY_FULL_SCAN）が無い"
fi

if grep -q 'QUALITY_SCOPE=all-files' "$GATE"; then
  ng "QUALITY_SCOPE に範囲の意味を持たせている（#135 D4: 軸を分けること）"
else
  ok "QUALITY_SCOPE（検査種別）と QUALITY_FULL_SCAN（範囲）が別軸のまま"
fi

say

# ---------------------------------------------------------------------------
# 挙動テスト用のフィクスチャ
# ---------------------------------------------------------------------------
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/shellcheck" <<'STUB'
#!/usr/bin/env bash
# テスト用スタブ。渡された引数を記録し、QC_STUB_BAD を含むファイルがあれば非0で終わる。
[ -n "${QC_STUB_LOG:-}" ] && printf '%s\n' "$*" >> "$QC_STUB_LOG"
rc=0
for f in "$@"; do
  case "$f" in -*) continue ;; esac
  if grep -q QC_STUB_BAD "$f" 2>/dev/null; then
    echo "$f: stub violation"
    rc=1
  fi
done
exit "$rc"
STUB
chmod +x "$TMPROOT/bin/shellcheck"

STUB_LOG="$TMPROOT/stub.log"
REPO=""

g() {
  git -C "$REPO" -c user.name=qc -c user.email=qc@example.com -c commit.gpgsign=false "$@"
}

# make_repo <名前> [初期ブランチ]
#   main 上に「変更しないきれいなスクリプト」と「変更しない壊れたスクリプト」を置く。
#   壊れたほうが検査対象に入るかどうかが本 issue の主目的の観測点。
make_repo() {
  local name="$1" branch="${2:-main}"
  REPO="$TMPROOT/$name"
  mkdir -p "$REPO/scripts"
  cp "$ROOT/$GATE" "$REPO/scripts/quality-check.sh"
  git init -q "$REPO" >/dev/null 2>&1
  git -C "$REPO" symbolic-ref HEAD "refs/heads/$branch"
  printf '#!/usr/bin/env bash\necho untouched-ok\n' > "$REPO/untouched_ok.sh"
  printf '#!/usr/bin/env bash\n# QC_STUB_BAD 既存の指摘を持つが今回は触らないファイル\n' \
    > "$REPO/untouched_bad.sh"
  printf '#!/usr/bin/env bash\necho touched\n' > "$REPO/touched.sh"
  printf '#!/usr/bin/env bash\necho extensionless\n' > "$REPO/tool-x"
  chmod +x "$REPO/tool-x"
  g add -A >/dev/null 2>&1
  g commit -q -m "base" >/dev/null 2>&1
}

# run_gate [環境変数の代入...] — フィクスチャ内で quality-check を実行する
#   ★ 呼び出し元の QUALITY_* を必ず落とす。quality-check.sh 自身がこのテストを
#     呼ぶため、`QUALITY_FULL_SCAN=1 bash scripts/quality-check.sh` の実行が
#     そのまま全フィクスチャに漏れて偽 FAIL になる（実際に踏んだ）。
RUN_OUT=""
RUN_RC=0
run_gate() {
  : > "$STUB_LOG"
  RUN_OUT="$(cd "$REPO" && env -u QUALITY_FULL_SCAN -u QUALITY_BASE_BRANCH -u QUALITY_SCOPE \
    "$@" QC_STUB_LOG="$STUB_LOG" \
    PATH="$TMPROOT/bin:$PATH" bash scripts/quality-check.sh 2>&1)"
  RUN_RC=$?
}

scanned() { grep -q -- "$1" "$STUB_LOG" 2>/dev/null; }
outhas() { case "$RUN_OUT" in *"$1"*) return 0 ;; esac; return 1; }

# ---------------------------------------------------------------------------
# V1: 変更が無ければ対象0件（skip 表示）
# ---------------------------------------------------------------------------
say "[behavior] 変更ファイル限定"

make_repo v1
g checkout -q -b feature/none
run_gate
if [ "$RUN_RC" -eq 0 ] && outhas "変更されたシェルスクリプトが無い"; then
  ok "V1: 変更が無いとき shellcheck は対象0件で skip される"
else
  ng "V1: 変更0件のときの skip 表示が無い (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V2 / V3: 触ったファイルだけが対象、触っていない壊れたファイルがあっても PASS
# ---------------------------------------------------------------------------
make_repo v3
g checkout -q -b feature/touch
printf '#!/usr/bin/env bash\necho touched-updated\n' > "$REPO/touched.sh"
g add -A >/dev/null 2>&1
g commit -q -m "touch" >/dev/null 2>&1
run_gate
if scanned "touched.sh" && ! scanned "untouched_ok.sh"; then
  ok "V2: 変更した1ファイルだけが検査系に渡る"
else
  ng "V2: 変更ファイル以外も渡っている（scanned: $(cat "$STUB_LOG")）"
fi
if [ "$RUN_RC" -eq 0 ] && ! scanned "untouched_bad.sh"; then
  ok "V3: 触っていない壊れたスクリプトがあっても PASS する（本 issue の主目的）"
else
  ng "V3: 触っていないファイルの既存指摘で落ちている (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V4: 変更ファイルに違反があれば FAIL（positive control）
# ---------------------------------------------------------------------------
make_repo v4
g checkout -q -b feature/break
printf '#!/usr/bin/env bash\n# QC_STUB_BAD\n' > "$REPO/touched.sh"
g add -A >/dev/null 2>&1
g commit -q -m "break" >/dev/null 2>&1
run_gate
if [ "$RUN_RC" -ne 0 ] && outhas "Quality checks FAILED"; then
  ok "V4: 変更ファイルの違反は FAIL する（検査が実際に効いている）"
else
  ng "V4: 変更ファイルの違反を見逃した (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V16: 未追跡の新規 .sh が対象に入る
# ---------------------------------------------------------------------------
make_repo v16
g checkout -q -b feature/untracked
printf '#!/usr/bin/env bash\n# QC_STUB_BAD\n' > "$REPO/brand_new.sh"
run_gate
if scanned "brand_new.sh" && [ "$RUN_RC" -ne 0 ]; then
  ok "V16: 未追跡の新規 .sh が検査対象に入る"
else
  ng "V16: 未追跡の新規 .sh が素通りしている (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V17: 拡張子なしの shebang スクリプトの変更が対象に入る
# ---------------------------------------------------------------------------
make_repo v17
g checkout -q -b feature/extensionless
printf '#!/usr/bin/env bash\n# QC_STUB_BAD\n' > "$REPO/tool-x"
g add -A >/dev/null 2>&1
g commit -q -m "edit extensionless" >/dev/null 2>&1
run_gate
if scanned "tool-x" && [ "$RUN_RC" -ne 0 ]; then
  ok "V17: 拡張子なし shebang スクリプトの変更が対象に入る（拡張子マッチだけにしない）"
else
  ng "V17: 拡張子なしスクリプトが素通りしている (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V14: .sh を削除した変更で落ちない（--diff-filter=d）
# ---------------------------------------------------------------------------
make_repo v14
g checkout -q -b feature/delete
g rm -q untouched_ok.sh >/dev/null 2>&1
g commit -q -m "delete" >/dev/null 2>&1
run_gate
if [ "$RUN_RC" -eq 0 ] && ! scanned "untouched_ok.sh"; then
  ok "V14: 削除されたファイルは検査系に渡らない"
else
  ng "V14: 削除ファイルを渡して落ちている (rc=$RUN_RC)"
fi

say

# ---------------------------------------------------------------------------
# V5 / V8: 全件走査と表示
# ---------------------------------------------------------------------------
say "[behavior] 範囲の表示と切り替え"

make_repo v5
g checkout -q -b feature/full
run_gate QUALITY_FULL_SCAN=1
if scanned "untouched_bad.sh" && [ "$RUN_RC" -ne 0 ] && outhas "全件走査（QUALITY_FULL_SCAN=1）"; then
  ok "V5: QUALITY_FULL_SCAN=1 で全件走査になる"
else
  ng "V5: QUALITY_FULL_SCAN=1 が効いていない (rc=$RUN_RC)"
fi

# 全件走査は限定走査の**厳密な上位集合**であること（フォールバックの前提）。
# 未追跡の新規スクリプトが全件走査から漏れると、限定走査より弱い場所ができてしまう。
printf '#!/usr/bin/env bash\n# QC_STUB_BAD\n' > "$REPO/brand_new.sh"
run_gate QUALITY_FULL_SCAN=1
if scanned "brand_new.sh" && scanned "untouched_bad.sh"; then
  ok "V5: 全件走査は限定走査の上位集合（未追跡の新規ファイルも含む）"
else
  ng "V5: 全件走査が未追跡ファイルを取りこぼしている（限定走査より弱い）"
fi

make_repo v8
g checkout -q -b feature/show
printf '#!/usr/bin/env bash\necho changed\n' > "$REPO/touched.sh"
g add -A >/dev/null 2>&1
g commit -q -m "touch" >/dev/null 2>&1
run_gate
if outhas "対象範囲: 変更ファイルのみ" && outhas "QUALITY_FULL_SCAN=1" && outhas "base: "; then
  ok "V8: 限定時に範囲・件数・解決した base・全件への導線が表示される"
else
  ng "V8: 限定の表示が不足している"
fi
if outhas "files, 変更ファイルのみ"; then
  ok "V8: 検査名に件数と範囲が入る（shellcheck (N files, 変更ファイルのみ)）"
else
  ng "V8: 検査名に範囲が出ていない"
fi

# ---------------------------------------------------------------------------
# V7 / V13: QUALITY_BASE_BRANCH
# ---------------------------------------------------------------------------
make_repo v7
g branch base-x >/dev/null 2>&1
g checkout -q -b feature/base
printf '#!/usr/bin/env bash\necho changed\n' > "$REPO/touched.sh"
g add -A >/dev/null 2>&1
g commit -q -m "touch" >/dev/null 2>&1
run_gate QUALITY_BASE_BRANCH=base-x
if [ "$RUN_RC" -eq 0 ] && outhas "base: base-x"; then
  ok "V7: QUALITY_BASE_BRANCH で base を明示できる"
else
  ng "V7: QUALITY_BASE_BRANCH が使われていない (rc=$RUN_RC)"
fi

run_gate QUALITY_BASE_BRANCH=no-such-ref-xyz
if [ "$RUN_RC" -ne 0 ] && outhas "QUALITY_BASE_BRANCH='no-such-ref-xyz' を解決できません"; then
  ok "V13: 無効な QUALITY_BASE_BRANCH は失敗する（黙って既定に落ちない）"
else
  ng "V13: 無効な QUALITY_BASE_BRANCH が握り潰されている (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V6: base ref を解決できないとき全件へフォールバックし、理由を表示する
# ---------------------------------------------------------------------------
make_repo v6 feat-only
run_gate
if outhas "全件走査へフォールバック" && outhas "理由:" && scanned "untouched_bad.sh"; then
  ok "V6: base 解決不能時は理由を表示して全件走査にフォールバックする"
else
  ng "V6: フォールバックまたは理由表示が無い (rc=$RUN_RC)"
fi

# ---------------------------------------------------------------------------
# V15: QUALITY_SCOPE=docs では範囲計算をしない
# ---------------------------------------------------------------------------
make_repo v15
g checkout -q -b feature/docs
run_gate QUALITY_SCOPE=docs
if ! outhas "対象範囲:" && ! outhas "base: " && [ "$RUN_RC" -eq 0 ]; then
  ok "V15: QUALITY_SCOPE=docs では範囲計算の表示が出ない"
else
  ng "V15: docs モードで範囲計算が動いている (rc=$RUN_RC)"
fi

say
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
