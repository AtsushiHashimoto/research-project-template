#!/usr/bin/env bash
# ============================================================
# ワークフローに必須の Claude Code フックを .claude/settings.json に登録する（単一情報源）
# [Template] research-project-template 由来
# ============================================================
#
# 登録するもの: SessionStart → scripts/session-context.sh
#   （/clear・/compact・再開のたびに、issue の最新の引き継ぎと epic 前提を文脈に戻す。
#    .claude/rules/template/deliverables.md「セッションの区切り」）
#
# .claude/settings.json はプロジェクトの設定（権限など）も持つので、ファイルごと配布せず、
# install / /template-sync の両方からこのスクリプトで**追記だけ**する（ensure-gitignore.sh と同じ形）。
# 既に同じコマンドが登録されていれば何もしない。既存の設定・他のフックは消さない。
#
# Usage:
#   bash scripts/ensure-claude-hooks.sh [--root <dir>] [--check]
#
# Exit codes:
#   0  登録済み / 追記完了
#   1  --check で未登録、jq が無い、settings.json が JSON として読めない
#   2  引数エラー
set -uo pipefail

ROOT=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)  ROOT="${2:-}"; shift 2 || { echo "ERROR: --root に値が要る" >&2; exit 2; } ;;
    --check) CHECK=1; shift ;;
    *) echo "usage: $0 [--root <dir>] [--check]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: git リポジトリ外。--root を指定" >&2; exit 2; }

SCRIPT_REL="scripts/session-context.sh"
COMMAND="bash \"\$CLAUDE_PROJECT_DIR/$SCRIPT_REL\""
SETTINGS="$ROOT/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq が無いため .claude/settings.json を更新できない" >&2; exit 1; }

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null || { echo "ERROR: $SETTINGS が JSON として読めない（手で直してから再実行）" >&2; exit 1; }
  CUR=$(cat "$SETTINGS")
else
  CUR='{}'
fi

if jq -e --arg s "$SCRIPT_REL" \
     '[.hooks.SessionStart[]?.hooks[]?.command // empty | select(contains($s))] | length > 0' \
     <<<"$CUR" >/dev/null; then
  echo "フック登録済み: SessionStart → $SCRIPT_REL"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  echo "未登録: SessionStart → $SCRIPT_REL（追記: bash scripts/ensure-claude-hooks.sh）"
  exit 1
fi

mkdir -p "$ROOT/.claude"
TMP=$(mktemp "$ROOT/.claude/settings.json.XXXXXX") || exit 1
if jq --arg c "$COMMAND" \
     '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{hooks: [{type: "command", command: $c, timeout: 30}]}])' \
     <<<"$CUR" > "$TMP"; then
  mv "$TMP" "$SETTINGS"
  echo "追記: SessionStart → $SCRIPT_REL（$SETTINGS）"
else
  rm -f "$TMP"
  echo "ERROR: $SETTINGS を更新できない" >&2
  exit 1
fi
