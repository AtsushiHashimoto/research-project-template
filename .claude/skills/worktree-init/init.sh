#!/usr/bin/env bash
# Wrapper for /worktree/init skill
# Calls scripts/init-data.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec "$REPO_ROOT/scripts/init-data.sh" "$@"
