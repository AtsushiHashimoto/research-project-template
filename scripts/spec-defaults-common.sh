#!/usr/bin/env bash
# ============================================================
# .spec/*.md の「既定節」を扱う共通処理
# [Template] research-project-template 由来
# ============================================================
#
# **source 専用。単独では実行しない。** 以下から読み込まれる:
#   - scripts/sync-spec-defaults.sh              … 既定節の差し替え（下流プロジェクトの sync）
#   - scripts/template-contribute-detect.sh      … 既定節の差分検出（還流候補の抽出）
#
# 既定節の定義（仕様 #100 D2）:
#   `^# 既定の` の行から `^# プロジェクト固有` の**直前**まで。
#   `# プロジェクト固有` 以降はプロジェクト固有節であり、テンプレートは一切触らない。
#
# マーカーの位置を2箇所で定義しないための単一情報源。

# SPEC_DEFAULT_FILES / SPEC_AUTOREVIEWER_RE は読み込み側のスクリプトが使う（SC2034 は誤検知）
# shellcheck disable=SC2034
SPEC_DEFAULT_FILES=(core-rules.md invariants.md known-issues.md)
SPEC_DEFAULT_START_RE='^# 既定の'
SPEC_DEFAULT_END_RE='^# プロジェクト固有'
# shellcheck disable=SC2034
SPEC_AUTOREVIEWER_RE='^## auto-reviewer への指示'

# spec_bounds <file> → "<start> <end>"（1-origin の行番号）
#   start = `# 既定の` の行、end = `# プロジェクト固有` の行。
#   既定節は start 行から end-1 行まで。
#   どちらかが無い / 順序が逆の場合は何も出力せず非0で返る。
spec_bounds() {
  [ -f "$1" ] || return 1
  awk -v s_re="$SPEC_DEFAULT_START_RE" -v e_re="$SPEC_DEFAULT_END_RE" '
    s == 0 && $0 ~ s_re { s = NR; next }
    s > 0 && e == 0 && $0 ~ e_re { e = NR }
    END { if (s > 0 && e > s) { print s, e; exit 0 } exit 1 }
  ' "$1"
}

# spec_extract_default <file> → 既定節を stdout に出力（マーカー不在なら非0）
spec_extract_default() {
  local bounds start end
  bounds=$(spec_bounds "$1") || return 1
  start=${bounds%% *}
  end=${bounds##* }
  sed -n "${start},$((end - 1))p" "$1"
}
