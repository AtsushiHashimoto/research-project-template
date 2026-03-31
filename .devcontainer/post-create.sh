#!/bin/bash
# ============================================================
# Common post-create setup (shared between CPU and GPU)
# [Template] research-project-template 由来
# ============================================================
set -e

PROJECT_NAME=${1:-$(basename "$(pwd)")}

# Claude Code config ownership
sudo chown -R "$(id -u):$(id -g)" /home/vscode/.claude

# Symlink for claude settings
ln -sf /home/vscode/.claude/.claude.json /home/vscode/.claude.json

# Deterministic machine-id (per project)
echo -n "devcontainer-${PROJECT_NAME}" | md5sum | cut -c1-32 | sudo tee /etc/machine-id > /dev/null

# claude-san symlink
sudo ln -sf "$(pwd)/claude-san" /usr/local/bin/claude-san
