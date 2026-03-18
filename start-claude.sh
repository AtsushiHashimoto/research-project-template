#!/bin/bash
# Claude Code + autoclaude セットアップスクリプト
# rate limit 後に自動再開するための環境を起動

SESSION_NAME="${1:-claude-work}"

# 既存セッションがあれば接続、なければ新規作成
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "既存セッションに接続: $SESSION_NAME"
    tmux attach -t "$SESSION_NAME"
else
    echo "新規セッション作成: $SESSION_NAME"
    tmux new-session -d -s "$SESSION_NAME"
    tmux send-keys -t "$SESSION_NAME" 'claude' Enter
    tmux split-window -h -l 25% -t "$SESSION_NAME"
    tmux send-keys -t "$SESSION_NAME" 'autoclaude' Enter
    tmux select-pane -t "$SESSION_NAME":0.0
    tmux attach -t "$SESSION_NAME"
fi

# 使い方:
#   ./start-claude.sh           # デフォルト: claude-work
#   ./start-claude.sh task1     # 別セッション: task1
#   ./start-claude.sh task2     # 別セッション: task2
