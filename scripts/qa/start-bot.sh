#!/bin/bash
# QA Bot 起動スクリプト
# .env が設定されていれば バックグラウンドで起動

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/data/local/qa-bot.log"

cd "$PROJECT_ROOT"

# .env の存在確認
if [ ! -f .env ]; then
    echo "[QA Bot] .env not found, skipping"
    exit 0
fi

# トークンの確認
source .env 2>/dev/null || true
if [ -z "$SLACK_BOT_TOKEN" ] && [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo "[QA Bot] No bot token configured, skipping"
    exit 0
fi

# ログディレクトリ作成
mkdir -p "$(dirname "$LOG_FILE")"

# 既存プロセスの確認
if pgrep -f "python.*qa.*bot" > /dev/null 2>&1; then
    echo "[QA Bot] Already running"
    exit 0
fi

# バックグラウンドで起動
echo "[QA Bot] Starting in background (log: $LOG_FILE)"
export PYTHONPATH="$PROJECT_ROOT/scripts:$PYTHONPATH"
nohup python -m qa >> "$LOG_FILE" 2>&1 &
echo "[QA Bot] PID: $!"
