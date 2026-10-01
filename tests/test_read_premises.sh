#!/usr/bin/env bash
# read-premises.sh の回帰テスト（gh を呼ばない。--epic-body-file と一時 invariants で決定的に動く）
# shellcheck disable=SC2015,SC2016  # ok/ng は常に 0 を返すので A&&B||C で安全 / ``` はリテラル
set -uo pipefail
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd); S="$ROOT/scripts/read-premises.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()   { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng()   { echo "FAIL $1"; FAIL=1; }
has()  { grep -qF -- "$2" <<<"$1" && ok "$3" || ng "$3"; }
hasnt(){ grep -qF -- "$2" <<<"$1" && ng "$3" || ok "$3"; }

cat > "$TMP/inv.md" <<'X'
# 既定
### INV-D01: x
# プロジェクト固有の設計判断
## ★ プロジェクト大前提（ユーザー確定事項）
- **P-01** カメラは動く
## 別の節
- 大前提ではない
X
export PREMISES_INVARIANTS="$TMP/inv.md"
mkdir -p "$TMP/nogh"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"

# 1: 前提節の後に別の ## 見出し
printf '## ゴール\ng\n## 前提（ユーザー確定事項）\n- E1\n### 小見出し\n- E2\n## 完了条件\n- c\n' > "$TMP/b1"
out=$(bash "$S" --epic-body-file "$TMP/b1" 2>/dev/null)
has "$out" "P-01" "大前提を切り出す"; hasnt "$out" "大前提ではない" "大前提の次節で止まる"
has "$out" "E2" "### は節内として残す"; hasnt "$out" "完了条件" "次の ## で止まる"
# 2: 本文末尾の前提節 + CRLF
printf '## ゴール\r\ng\r\n## 前提（ユーザー確定事項）\r\n- E3\r\n' > "$TMP/b2"
out=$(bash "$S" --epic-body-file "$TMP/b2" 2>/dev/null)
has "$out" "- E3" "末尾の節・CRLF"; grep -q $'\r' <<<"$out" && ng "CR を除去" || ok "CR を除去"
# 3: 紛らわしい見出し（## 前提となる背景）には一致しない
printf '## 前提となる背景\n- NOT\n## 前提（ユーザー確定事項）\n- E4\n' > "$TMP/b3"
out=$(bash "$S" --epic-body-file "$TMP/b3" 2>/dev/null)
has "$out" "E4" "完全一致の見出し"; hasnt "$out" "NOT" "紛らわしい見出しを拾わない"
# 4: 前提節なし → 警告して 0
printf '## ゴール\ng\n' > "$TMP/b4"
out=$(bash "$S" --epic-body-file "$TMP/b4" 2>"$TMP/err"); rc=$?
[ $rc = 0 ] && ok "節なしは exit 0" || ng "節なしは exit 0"
has "$out" "前提節なし・未記入" "節なしを明示"; has "$(cat "$TMP/err")" "WARN" "節なしで警告"
# 5: 雛形のまま（<...> と HTML コメント）→ 未記入扱い
printf '## 前提（ユーザー確定事項）\n\n<この epic だけに効く前提>\n<!-- c -->\n## 完了条件\n' > "$TMP/b5"
out=$(bash "$S" --epic-body-file "$TMP/b5" 2>/dev/null)
has "$out" "前提節なし・未記入" "雛形は未記入扱い"; hasnt "$out" "この epic だけ" "雛形文言を渡さない"
# 6: コードブロック内の ## で切らない
printf '## 前提（ユーザー確定事項）\n- E6\n```\n## not heading\n```\n- E7\n## 完了条件\n' > "$TMP/b6"
out=$(bash "$S" --epic-body-file "$TMP/b6" 2>/dev/null)
has "$out" "E7" "コードブロック内の見出しで切らない"
# 7: 大前提節が無い invariants → 警告して節なしを明示
printf '# プロジェクト固有\n（未記入）\n' > "$TMP/inv2.md"
out=$(PREMISES_INVARIANTS="$TMP/inv2.md" bash "$S" --no-epic 2>"$TMP/err")
has "$out" "（節なし）" "大前提節なしを明示"; has "$(cat "$TMP/err")" "移行手順" "移行手順へ誘導"
# 8b: --epic-only は大前提を出さない／番号なしは exit 1（gh を呼ぶ経路は tests/test_handoff.sh で確認）
bash "$S" --epic-only 2>/dev/null; [ $? = 1 ] && ok "--epic-only 番号なしは exit 1" || ng "--epic-only 番号なしは exit 1"
out=$(PATH="$TMP/nogh:$PATH" bash "$S" --epic-only 5 2>/dev/null)
hasnt "$out" "P-01" "--epic-only は大前提を出さない"
# 8: 引数不正は exit 1
bash "$S" 2>/dev/null; [ $? = 1 ] && ok "引数なしは exit 1" || ng "引数なしは exit 1"

[ $FAIL = 0 ] && { [ "$QUIET" = 1 ] || echo "all passed"; exit 0; } || exit 1
