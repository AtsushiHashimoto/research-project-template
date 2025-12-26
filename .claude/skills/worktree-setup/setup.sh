#!/usr/bin/env bash
# Wrapper for /worktree/setup skill
# Calls scripts/setup-worktree.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec "$REPO_ROOT/scripts/setup-worktree.sh" "$@"
