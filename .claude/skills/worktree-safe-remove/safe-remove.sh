#!/usr/bin/env bash
# Wrapper for /worktree/safe-remove skill
# Calls scripts/safe-remove-worktree.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec "$REPO_ROOT/scripts/safe-remove-worktree.sh" "$@"
