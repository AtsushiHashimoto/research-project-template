#!/usr/bin/env bash
# session-context.sh — SessionStart フック（startup / resume / clear / compact）。stdout がセッションの文脈に入る。
#
# 次のセッションが「何をしていたか」を issue から取り戻すための短い出力を作る
# （.claude/rules/template/deliverables.md「セッションの区切り」）。登録は scripts/ensure-claude-hooks.sh。
#
#   bash scripts/session-context.sh [<issue番号>]
#
# issue の決め方: 引数 → 現在のブランチ名の数字 → handoff.sh が記録した最後の引き継ぎ先。
# 出力: 対象 issue / 最新の引き継ぎコメント / epic 前提（大前提は CLAUDE.md の import で読み込み済みなので出さない）/
#       作業中の worktree 一覧。
#
# ★ セッションの開始を妨げない: gh の失敗・時間切れは 1 行の注記にして、常に exit 0。
#   stdin のフック入力（JSON）は読み捨てる。
set -uo pipefail

[ -t 0 ] || cat >/dev/null 2>&1
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
TIMEOUT="${SESSION_CONTEXT_TIMEOUT:-10}"
if command -v timeout >/dev/null 2>&1; then run() { timeout "$TIMEOUT" "$@"; }; else run() { "$@"; }; fi

BRANCH=$(git branch --show-current 2>/dev/null || true)
ISSUE="${1:-}"
ISSUE="${ISSUE#\#}"
SOURCE="引数"
if [ -z "$ISSUE" ] && [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
  ISSUE=$(grep -oE '[0-9]+' <<<"$BRANCH" | head -n1)
  SOURCE="ブランチ $BRANCH"
fi
if [ -z "$ISSUE" ]; then
  ISSUE=$(bash scripts/handoff.sh last 2>/dev/null | cut -f1)
  SOURCE="最後の引き継ぎ先"
fi

echo "# セッションの文脈（scripts/session-context.sh）"
echo
if [ -n "$ISSUE" ]; then
  TITLE=$(run gh issue view "$ISSUE" --json title,state -q '"\(.title)（\(.state)）"' 2>/dev/null) \
    || TITLE="（gh で取得できない）"
  echo "対象: #$ISSUE $TITLE ← $SOURCE"
  echo
  HANDOFF=$(run bash scripts/handoff.sh read "$ISSUE" 2>/dev/null)
  if [ -n "$HANDOFF" ]; then
    printf '%s\n' "$HANDOFF"
  else
    echo "（#$ISSUE に引き継ぎコメントなし、または取得できない）"
  fi
  if [ -f scripts/read-premises.sh ]; then
    PREM=$(run bash scripts/read-premises.sh --epic-only "$ISSUE" 2>/dev/null) \
      || PREM="（epic 前提を取得できない。作業前に bash scripts/read-premises.sh $ISSUE を実行）"
    echo
    printf '%s\n' "$PREM"
  fi
else
  echo "対象の issue を特定できない（main 上で、引き継ぎの記録も無い）。"
fi

# 作業中の worktree（main 以外のブランチ）
WT=$(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree / { p = substr($0, 10) }
  /^branch /   { b = substr($0, 8); sub(/^refs\/heads\//, "", b); if (b != "main") print "- " p "  (" b ")" }')
if [ -n "$WT" ]; then
  echo
  echo "## 作業中の worktree"
  printf '%s\n' "$WT"
fi
echo
echo "別の issue を続けるときは: bash scripts/session-context.sh <issue番号>"
exit 0
