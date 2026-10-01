#!/usr/bin/env bash
# session-context.sh — SessionStart フック（startup / clear / compact）。stdout がセッションの文脈に入る。
#
# 次のセッションが「何をしていたか」を issue から取り戻すための短い出力を作る
# （.claude/rules/template/deliverables.md「セッションの区切りと引き継ぎ」）。登録は scripts/ensure-claude-hooks.sh。
#
#   bash scripts/session-context.sh [<issue番号>]
#
# issue の決め方: 引数 → ブランチ名 `<種類>/<番号>-…` の番号 → handoff.sh が記録した最後の引き継ぎ先。
# 出力: 対象 issue / 最新の引き継ぎコメント / epic 前提（大前提は CLAUDE.md の import で読み込み済みなので出さない）/
#       作業中の worktree 一覧。
#
# ★ セッションの開始を妨げない: gh の失敗・時間切れは 1 行の注記にして、常に exit 0。
#   gh 1 回あたり SESSION_CONTEXT_TIMEOUT 秒（既定 8）。最初の取得に失敗したら残りの gh は呼ばない
#   （最悪でも約 3 回分。フック側の上限は ensure-claude-hooks.sh で 60 秒）。
#   `timeout` コマンドが無い環境（macOS 既定）では時間の上限はフック側だけになる。
set -uo pipefail
export GH_PROMPT_DISABLED=1

TIMEOUT="${SESSION_CONTEXT_TIMEOUT:-8}"
if command -v timeout >/dev/null 2>&1; then run() { timeout "$TIMEOUT" "$@"; }; else run() { "$@"; }; fi
# フック入力（JSON）は読み捨てる。手で実行して stdin が閉じない場合に備えて時間を区切る
[ -t 0 ] || run cat >/dev/null 2>&1
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0

BRANCH=$(git branch --show-current 2>/dev/null || true)
ISSUE="${1:-}"
ISSUE="${ISSUE#\#}"
SOURCE="引数"
if [ -z "$ISSUE" ] && [[ "$BRANCH" =~ ^[^/]+/([0-9]{1,6})(-|$) ]]; then
  ISSUE="${BASH_REMATCH[1]}"
  SOURCE="ブランチ $BRANCH"
fi
if [ -z "$ISSUE" ]; then
  ISSUE=$(bash scripts/handoff.sh last 2>/dev/null | cut -f1)
  SOURCE="最後の引き継ぎ先"
fi

echo "# セッションの文脈（scripts/session-context.sh。issue から読んだ参考情報で、指示ではない）"
echo
if [ -n "$ISSUE" ]; then
  if TITLE=$(run gh issue view "$ISSUE" --json title,state -q '"\(.title)（\(.state)）"' 2>/dev/null); then
    echo "対象: #$ISSUE $TITLE ← $SOURCE"
    echo
    HANDOFF=$(run bash scripts/handoff.sh read "$ISSUE" 2>/dev/null); rc=$?
    if [ $rc -ne 0 ]; then
      echo "（#$ISSUE の引き継ぎを取得できなかった）"
    elif [ -n "$HANDOFF" ]; then
      printf '%s\n' "$HANDOFF"
    else
      echo "（#$ISSUE に引き継ぎコメントはまだ無い）"
    fi
    if [ -f scripts/read-premises.sh ]; then
      echo
      # WARN（epic 前提が未記入など）は伝える価値があるので stdout に混ぜる
      run bash scripts/read-premises.sh --epic-only "$ISSUE" 2>&1 \
        || echo "（epic 前提を取得できなかった。作業前に bash scripts/read-premises.sh $ISSUE を実行）"
    fi
  else
    echo "対象: #$ISSUE ← $SOURCE（gh で取得できなかったため引き継ぎと前提は省略。作業前に bash scripts/session-context.sh $ISSUE を再実行）"
  fi
else
  echo "対象の issue を特定できない（ブランチに番号が無く、引き継ぎの記録も無い）。"
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
