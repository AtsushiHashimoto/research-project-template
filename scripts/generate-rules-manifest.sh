#!/usr/bin/env bash
# ============================================================
# .claude/rules/template/MANIFEST.sha256 の生成
# [Template] research-project-template 由来
# ============================================================
#
# テンプレート開発者用。`.claude/rules/template/` のルールを追加・変更・削除したら
# 本スクリプトを実行し、生成された MANIFEST.sha256 を同じコミットに含めること。
#
# MANIFEST は下流プロジェクトの `/template-sync` が
# 「前回 sync 以降にローカルで改変されたルール（＝還流候補）」を検出するために使う。
# MANIFEST が古いと、無改変のファイルが改変扱いで退避される（安全側だが騒がしい）。
#
# Usage:
#   bash scripts/generate-rules-manifest.sh [<rules-template-dir>]
#   bash scripts/generate-rules-manifest.sh --check [<rules-template-dir>]
#   bash scripts/generate-rules-manifest.sh --help
#
# 冪等: 内容が変わっていなければ2回実行しても出力は一致する。
# --check は生成せず整合だけを検査する（scripts/quality-check.sh から呼ばれる）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=rules-manifest-common.sh
. "$SCRIPT_DIR/rules-manifest-common.sh"

usage() {
  cat <<'EOF'
.claude/rules/template/MANIFEST.sha256 を生成する（テンプレート開発者用）。

Usage:
  bash scripts/generate-rules-manifest.sh [<rules-template-dir>]
  bash scripts/generate-rules-manifest.sh --check [<rules-template-dir>]
  bash scripts/generate-rules-manifest.sh --help

  <rules-template-dir>  既定: <リポジトリルート>/.claude/rules/template

Options:
  --check   生成せず、実ファイルと MANIFEST の整合だけを検査する。
            不整合（未登録・欠落・ハッシュ不一致・MANIFEST 不在）なら非0 exit。

ルールを追加・変更・削除したら実行し、生成された MANIFEST.sha256 を
同じコミットに含めること。冪等（内容が同じなら出力も同じ）。

Exit codes:
  0  成功（--check では整合）
  1  失敗（--check では不整合）
  2  引数エラー
EOF
}

CHECK_ONLY=false

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --check)
    CHECK_ONLY=true
    shift
    ;;
esac

if [ $# -gt 1 ]; then
  echo "ERROR: 引数が多すぎます" >&2
  usage >&2
  exit 2
fi

REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)
RULES_TEMPLATE_DIR="${1:-$REPO_ROOT/.claude/rules/template}"

if [ ! -d "$RULES_TEMPLATE_DIR" ]; then
  echo "ERROR: ディレクトリがありません: $RULES_TEMPLATE_DIR" >&2
  exit 1
fi

if $CHECK_ONLY; then
  manifest_check "$RULES_TEMPLATE_DIR" || exit 1
  echo "整合: ${RULES_TEMPLATE_DIR}/${RULES_MANIFEST_NAME}"
  exit 0
fi

COUNT=$(manifest_write "$RULES_TEMPLATE_DIR") || exit 1

echo "生成: ${RULES_TEMPLATE_DIR}/${RULES_MANIFEST_NAME}（${COUNT} ファイル）"
