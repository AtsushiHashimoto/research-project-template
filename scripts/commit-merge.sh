#!/bin/bash
# scripts/commit-merge.sh
#
# PRをマージし、worktreeをクリーンアップするスクリプト
#
# Usage:
#   ./scripts/commit-merge.sh <PR_NUMBER> [WORKTREE_PATH]
#
# Arguments:
#   PR_NUMBER     - マージするPR番号
#   WORKTREE_PATH - 削除するworktreeのパス（オプション）
#
# このスクリプトは以下を実行します:
# 1. PRをsquash merge
# 2. mainブランチを更新
# 3. worktreeを削除（指定された場合）
# 4. リモートブランチを削除
# 5. ローカルブランチを削除

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 引数チェック
if [ -z "$1" ]; then
    log_error "Usage: $0 <PR_NUMBER> [WORKTREE_PATH]"
    exit 1
fi

PR_NUMBER="$1"
WORKTREE_PATH="$2"  # オプション: 削除するworktreeのパス

# worktreeからブランチ名を取得（指定された場合）
BRANCH_TO_DELETE=""
if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
    BRANCH_TO_DELETE=$(git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null || true)
    log_info "Worktree指定: $WORKTREE_PATH (branch: $BRANCH_TO_DELETE)"
fi

# メインリポジトリのパスを取得
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')

# メインリポジトリにいることを確認
CURRENT_DIR=$(pwd)
if [ "$CURRENT_DIR" != "$MAIN_REPO" ]; then
    log_info "メインリポジトリへ移動..."
    cd "$MAIN_REPO"
fi

# PRをマージ（--delete-branchは使わない。worktree削除後にブランチを削除する）
log_info "PR #${PR_NUMBER} をマージ中..."
if ! gh pr merge "$PR_NUMBER" --squash; then
    log_error "PRのマージに失敗しました"
    exit 1
fi

log_info "PRのマージが完了しました"

# mainブランチを更新
log_info "mainブランチを更新中..."
git checkout main 2>/dev/null || true
git pull

# worktreeの削除（パスが指定された場合）
# ブランチ削除より先に行う必要がある
if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
    log_info "Worktreeを削除中: $WORKTREE_PATH"
    git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || {
        log_warn "Worktreeの自動削除に失敗しました。手動で削除してください:"
        log_warn "  git worktree remove $WORKTREE_PATH --force"
    }
fi

# リモートブランチの削除
if [ -n "$BRANCH_TO_DELETE" ] && [ "$BRANCH_TO_DELETE" != "main" ]; then
    log_info "リモートブランチを削除中: $BRANCH_TO_DELETE"
    git push origin --delete "$BRANCH_TO_DELETE" 2>/dev/null || {
        log_warn "リモートブランチの削除に失敗しました（既に削除済みの可能性）"
    }
fi

# ローカルブランチの削除
if [ -n "$BRANCH_TO_DELETE" ] && [ "$BRANCH_TO_DELETE" != "main" ]; then
    log_info "ローカルブランチを削除中: $BRANCH_TO_DELETE"
    git branch -D "$BRANCH_TO_DELETE" 2>/dev/null || {
        log_warn "ローカルブランチの削除に失敗しました（既に削除済みの可能性）"
    }
fi

log_info "クリーンアップ完了"
echo ""
echo "現在の状態:"
git status
