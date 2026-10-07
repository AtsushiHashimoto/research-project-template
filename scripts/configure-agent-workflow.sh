#!/usr/bin/env bash
# clone/worktree/同期後の入口。原本を複製せず、生成リンクと両フックだけを整える。
set -euo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel)}"
python3 "$ROOT/scripts/agent-skills.py" --root "$ROOT"
bash "$ROOT/scripts/ensure-claude-hooks.sh" --root "$ROOT"
python3 "$ROOT/scripts/ensure-codex-hooks.py" --root "$ROOT"
echo "[agent-workflow] configured; Codex hook trust requires /hooks; new skills require discovery"
