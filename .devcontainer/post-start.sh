#!/bin/bash
# ============================================================
# Post-start setup (runs every container start)
# [Template] research-project-template 由来
# claude-auto-retry install は postCreateCommand では .bashrc が
# updateRemoteUserUID により上書きされる可能性があるため、ここで実行
# ============================================================

# claude-auto-retry: .bashrc に claude() シェル関数を注入
claude-auto-retry install 2>/dev/null || true

# --dangerously-skip-permissions をデフォルトで付与
# claude-auto-retry の wrapper ブロック外に追記し、上書きされないようにする
BASHRC="$HOME/.bashrc"
SKIP_MARKER="# claude-skip-permissions"
if ! grep -q "$SKIP_MARKER" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'EOF'

# claude-skip-permissions
# devcontainer 内では常に --dangerously-skip-permissions を付与
_claude_orig=$(declare -f claude)
if [ -n "$_claude_orig" ]; then
  # claude-auto-retry の claude() 関数をラップ
  eval "$(echo "$_claude_orig" | sed 's/^claude ()/___claude_inner ()/')"
  claude() { ___claude_inner --dangerously-skip-permissions "$@"; }
else
  claude() { command claude --dangerously-skip-permissions "$@"; }
fi
unset _claude_orig
EOF
fi
