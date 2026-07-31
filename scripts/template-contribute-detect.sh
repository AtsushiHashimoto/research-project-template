#!/usr/bin/env bash
# ============================================================
# 還流候補（テンプレート由来ファイルのローカル改変）の検出
# [Template] research-project-template 由来
# ============================================================
#
# `/template-contribute` の検出処理の実体（仕様 #100 D4-a）。
#
# 判別基準:
#   **テンプレート由来パスの変更 = 還流候補。それ以外 = プロジェクト固有。**
#
#   テンプレート由来パス:
#     .claude/rules/template/       （MANIFEST.sha256 は生成物なので除外）
#     .claude/skills/
#     .claude/agents/
#     scripts/
#     .spec/*.md の**既定節のみ**（`# プロジェクト固有` 以降は還流しない）
#     .claude/rules/template.bak-*/ （sync が退避したローカル改変＝還流候補そのもの）
#
#   対象外（プロジェクト固有）:
#     .claude/rules/ 直下、.claude/CLAUDE.md、.spec/ の固有節、その他すべて
#
# 出力:
#   既定           … 還流候補の一覧（状態・パス）
#   --format paths … パスのみ1行1件（選択 UI やループ処理用）
#   --diff <path>  … 指定パスの unified diff（テンプレート → ローカル）
#
# Usage:
#   bash scripts/template-contribute-detect.sh --source <template-checkout-dir> [options]
#   bash scripts/template-contribute-detect.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=spec-defaults-common.sh
. "$SCRIPT_DIR/spec-defaults-common.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=rules-manifest-common.sh
. "$SCRIPT_DIR/rules-manifest-common.sh"

usage() {
  cat <<'EOF'
テンプレート由来ファイルのローカル改変（＝還流候補）を検出する。

Usage:
  bash scripts/template-contribute-detect.sh --source <template-checkout-dir> [options]

Options:
  --source <dir>        必須。テンプレート最新版を clone / 展開したディレクトリ
  --project-root <dir>  比較元のプロジェクト。既定はカレントの git リポジトリルート
  --format <list|paths> 出力形式。既定 list（人間向け）、paths は1行1パス
  --diff <path>         指定パスの unified diff を出力する（一覧のパスをそのまま渡す）
  -h, --help            この使い方を表示する

判別基準:
  テンプレート由来パスの変更 = 還流候補 / それ以外 = プロジェクト固有（対象外）

Exit codes:
  0  正常終了（候補0件を含む）
  1  失敗（テンプレートの取得失敗、--diff の対象が候補に無い等）
  2  引数エラー

Example:
  TMP_DIR=$(mktemp -d)
  git clone --depth 1 "$TEMPLATE_REPO" "$TMP_DIR/template" || exit 1
  bash scripts/template-contribute-detect.sh --source "$TMP_DIR/template"
  bash scripts/template-contribute-detect.sh --source "$TMP_DIR/template" \
      --diff .claude/rules/template/labels.md
EOF
}

# ---------------------------------------------------------------------------
# 引数
# ---------------------------------------------------------------------------
SOURCE_DIR=""
PROJECT_ROOT=""
FORMAT="list"
DIFF_PATH=""

if [ $# -eq 0 ]; then
  echo "ERROR: --source が指定されていません（引数なしでは実行しません）" >&2
  echo >&2
  usage >&2
  exit 2
fi

need_value() {
  if [ -z "$2" ]; then
    echo "ERROR: $1 には値が必要です" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      need_value "$1" "${2:-}"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --project-root)
      need_value "$1" "${2:-}"
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --format)
      need_value "$1" "${2:-}"
      FORMAT="$2"
      shift 2
      ;;
    --diff)
      need_value "$1" "${2:-}"
      DIFF_PATH="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      echo >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$SOURCE_DIR" ]; then
  echo "ERROR: --source は必須です" >&2
  exit 2
fi

case "$FORMAT" in
  list | paths) ;;
  *)
    echo "ERROR: --format は list か paths です: $FORMAT" >&2
    exit 2
    ;;
esac

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

if [ ! -d "$SOURCE_DIR/.claude" ]; then
  echo "ERROR: テンプレートの取得に失敗しています（.claude/ が見つかりません）: $SOURCE_DIR" >&2
  echo "  clone が失敗していないか、--source の指定が正しいかを確認してください。" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 候補の収集
#   1行 = <status>\t<display-path>\t<mode>\t<template-path>\t<local-path>
#   mode: file | specdefault
# ---------------------------------------------------------------------------
TMP_WORK=$(mktemp -d) || {
  echo "ERROR: 一時ディレクトリを作成できませんでした" >&2
  exit 1
}
trap 'rm -rf "$TMP_WORK"' EXIT

CANDIDATES="$TMP_WORK/candidates.tsv"
: >"$CANDIDATES"
WARNINGS=""

add_candidate() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >>"$CANDIDATES"
}

# compare_file <display-path> <template-path> <local-path>
compare_file() {
  local disp="$1" tpl="$2" loc="$3"
  if [ ! -f "$tpl" ]; then
    add_candidate "追加" "$disp" file "$tpl" "$loc"
  elif ! cmp -s "$tpl" "$loc"; then
    add_candidate "変更" "$disp" file "$tpl" "$loc"
  fi
}

# scan_dir <rel-dir> [<除外する相対パス>]
scan_dir() {
  local rel="$1" exclude="${2:-}"
  local root="$PROJECT_ROOT/$rel"
  local sub disp
  [ -d "$root" ] || return 0
  while IFS= read -r sub; do
    sub="${sub#./}"
    [ "$(basename "$sub")" = ".DS_Store" ] && continue
    [ -n "$exclude" ] && [ "$sub" = "$exclude" ] && continue
    disp="$rel/$sub"
    compare_file "$disp" "$SOURCE_DIR/$disp" "$root/$sub"
  done < <(cd "$root" && find . -type f | LC_ALL=C sort)
}

# --- テンプレート由来ディレクトリ ---
# MANIFEST.sha256 は generate-rules-manifest.sh の生成物であり、還流の対象にしない
scan_dir ".claude/rules/template" "$RULES_MANIFEST_NAME"
scan_dir ".claude/skills"
scan_dir ".claude/agents"
scan_dir "scripts"

# --- sync が退避したローカル改変（D1-b の template.bak-*/） ---
for bak in "$PROJECT_ROOT"/.claude/rules/template.bak-*/; do
  [ -d "$bak" ] || continue
  bakname=$(basename "$bak")
  for sub in template flat; do
    [ -d "$bak$sub" ] || continue
    while IFS= read -r rel; do
      rel="${rel#./}"
      [ "$(basename "$rel")" = ".DS_Store" ] && continue
      [ "$rel" = "$RULES_MANIFEST_NAME" ] && continue
      compare_file ".claude/rules/$bakname/$sub/$rel" \
        "$SOURCE_DIR/.claude/rules/template/$rel" "$bak$sub/$rel"
    done < <(cd "$bak$sub" && find . -type f | LC_ALL=C sort)
  done
done

# --- .spec/*.md の既定節のみ ---
for name in "${SPEC_DEFAULT_FILES[@]}"; do
  loc="$PROJECT_ROOT/.spec/$name"
  tpl="$SOURCE_DIR/.spec/$name"
  disp=".spec/$name (既定節)"
  [ -f "$loc" ] || continue
  if [ ! -f "$tpl" ]; then
    WARNINGS="${WARNINGS}  - ${disp} — テンプレート側にファイルがありません（比較不能）"$'\n'
    continue
  fi
  if ! spec_extract_default "$loc" >"$TMP_WORK/local-$name"; then
    WARNINGS="${WARNINGS}  - ${disp} — 既定節のマーカーが無いため比較できません"$'\n'
    continue
  fi
  if ! spec_extract_default "$tpl" >"$TMP_WORK/tpl-$name"; then
    WARNINGS="${WARNINGS}  - ${disp} — テンプレート側に既定節のマーカーがありません"$'\n'
    continue
  fi
  if ! cmp -s "$TMP_WORK/tpl-$name" "$TMP_WORK/local-$name"; then
    add_candidate "変更" "$disp" specdefault "$TMP_WORK/tpl-$name" "$TMP_WORK/local-$name"
  fi
done

# ---------------------------------------------------------------------------
# --diff <path>
# ---------------------------------------------------------------------------
if [ -n "$DIFF_PATH" ]; then
  line=$(awk -F'\t' -v p="$DIFF_PATH" '$2 == p { print; exit }' "$CANDIDATES")
  if [ -z "$line" ]; then
    echo "ERROR: 還流候補に含まれないパスです: $DIFF_PATH" >&2
    echo "  --format paths で候補一覧を確認してください。" >&2
    exit 1
  fi
  tpl=$(printf '%s' "$line" | cut -f4)
  loc=$(printf '%s' "$line" | cut -f5)
  [ -f "$tpl" ] || tpl=/dev/null
  diff -u --label "template/$DIFF_PATH" --label "local/$DIFF_PATH" "$tpl" "$loc"
  exit 0
fi

# ---------------------------------------------------------------------------
# 一覧出力
# ---------------------------------------------------------------------------
TOTAL=$(wc -l <"$CANDIDATES" | tr -d ' ')

if [ "$FORMAT" = "paths" ]; then
  cut -f2 "$CANDIDATES"
  exit 0
fi

echo "=== 還流候補の検出 ==="
echo "  template: $SOURCE_DIR"
echo "  project : $PROJECT_ROOT"
echo

if [ "$TOTAL" -eq 0 ]; then
  echo "還流候補はありません（テンプレート由来パスに差分なし）。"
else
  echo "還流候補 $TOTAL 件（テンプレート由来パスの変更）:"
  awk -F'\t' '{ printf "  [%s] %s\n", $1, $2 }' "$CANDIDATES"
  echo
  echo "unified diff の表示:"
  echo "  bash scripts/template-contribute-detect.sh --source <dir> --diff '<上のパス>'"
fi

if [ -n "$WARNINGS" ]; then
  echo
  echo "⚠️ 比較できなかった対象:"
  printf '%s' "$WARNINGS"
fi

echo
echo "判別基準: テンプレート由来パスの変更＝還流候補 / それ以外＝プロジェクト固有（対象外）"
exit 0
