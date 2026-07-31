#!/usr/bin/env bash
# Wrapper for /worktree/init skill
# Calls scripts/init-data.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# worktree の .git 参照を相対パス化（ホスト/コンテナ間でパスが異なるため）
if [ -x "$REPO_ROOT/scripts/configure-worktree-paths.sh" ]; then
  "$REPO_ROOT/scripts/configure-worktree-paths.sh" || true
fi

# GitHub ラベルのプロビジョニング
if [ -x "$REPO_ROOT/scripts/setup-labels.sh" ]; then
  "$REPO_ROOT/scripts/setup-labels.sh" || true
fi

exec "$REPO_ROOT/scripts/init-data.sh" "$@"
