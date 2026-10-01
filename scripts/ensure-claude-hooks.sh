#!/usr/bin/env bash
# ============================================================
# ワークフローに必須の Claude Code フックを .claude/settings.json に登録する（単一情報源）
# [Template] research-project-template 由来
# ============================================================
#
# 登録するもの: SessionStart → scripts/session-context.sh
#   （起動・/clear・/compact のたびに、issue の最新の引き継ぎと epic 前提を文脈に戻す。
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
# スクリプトがまだ無い（sync で scripts/ を取り込む前など）ときは何もしない。セッション開始をエラーにしない
COMMAND="[ ! -f \"\$CLAUDE_PROJECT_DIR/$SCRIPT_REL\" ] || bash \"\$CLAUDE_PROJECT_DIR/$SCRIPT_REL\""
# resume は会話がそのまま戻るので出さない（同じ内容を重ねない）
MATCHER="startup|clear|compact"
SETTINGS="$ROOT/.claude/settings.json"
P="[claude-hooks]"

command -v jq >/dev/null 2>&1 || { echo "$P ERROR: jq が無いため .claude/settings.json を更新できない" >&2; exit 1; }

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null || { echo "$P ERROR: $SETTINGS が JSON として読めない（手で直してから再実行）" >&2; exit 1; }
  CUR=$(cat "$SETTINGS")
  # 空ファイル（jq empty は通る）は {} とみなす
  [ -n "$(tr -d '[:space:]' <<<"$CUR")" ] || CUR='{}'
else
  CUR='{}'
fi

# 登録済みの判定は、同じコマンドが入っているか（完全一致。matcher は問わない＝プロジェクトが変えた matcher を尊重し、
# 二重登録で 2 回走らせない）。形の崩れた設定は jq エラー＝異常として止める
FOUND=$(jq --arg c "$COMMAND" '
  [ (.hooks.SessionStart // [])[]
    | select(type == "object")
    | (.hooks // [])[]
    | select(type == "object" and .command == $c) ] | length' <<<"$CUR") \
  || { echo "$P ERROR: $SETTINGS の hooks.SessionStart の形が想定と違う（手で確認）" >&2; exit 1; }
[[ "$FOUND" =~ ^[0-9]+$ ]] || { echo "$P ERROR: $SETTINGS の hooks.SessionStart の形が想定と違う（手で確認）" >&2; exit 1; }

if [ "$FOUND" -gt 0 ]; then
  echo "$P フック登録済み: SessionStart（$MATCHER）→ $SCRIPT_REL"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  echo "$P 未登録: SessionStart（$MATCHER）→ $SCRIPT_REL（追記: bash scripts/ensure-claude-hooks.sh）"
  exit 1
fi

mkdir -p "$ROOT/.claude"
NEW=$(jq --arg c "$COMMAND" --arg m "$MATCHER" \
  '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{matcher: $m, hooks: [{type: "command", command: $c, timeout: 60}]}])' \
  <<<"$CUR") || { echo "$P ERROR: $SETTINGS の更新内容を作れない" >&2; exit 1; }
# 書き込みは既存ファイルへの上書き（mv で置き換えると権限・symlink が変わる）
if printf '%s\n' "$NEW" > "$SETTINGS"; then
  echo "$P 追記: SessionStart（$MATCHER）→ $SCRIPT_REL（$SETTINGS）"
else
  echo "$P ERROR: $SETTINGS に書き込めない" >&2
  exit 1
fi
