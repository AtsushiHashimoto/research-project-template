#!/bin/bash
# scripts/commit-merge.sh
#
# Worktree内からでも安全にPRをマージし、クリーンアップを実行するスクリプト
#
# Usage:
#   ./scripts/commit-merge.sh <PR_NUMBER>
#
# このスクリプトは以下を実行します:
# 1. メインリポジトリへ移動（worktree対応）
# 2. PRをsquash merge
# 3. mainブランチを更新
# 4. worktreeを削除（ブランチ削除より先に行う）
# 5. リモートブランチを削除
# 6. ローカルブランチを削除

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
    log_error "Usage: $0 <PR_NUMBER>"
    exit 1
fi

PR_NUMBER="$1"

# 現在のworktreeパスを記録（後で削除するため）
CURRENT_DIR=$(pwd)
CURRENT_BRANCH=$(git branch --show-current)

# メインリポジトリのパスを取得
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')

# worktree内かどうかを判定
IS_WORKTREE=false
if [ "$CURRENT_DIR" != "$MAIN_REPO" ]; then
    IS_WORKTREE=true
    log_info "Worktree内で実行中: $CURRENT_DIR"
    log_info "メインリポジトリ: $MAIN_REPO"
fi

# メインリポジトリへ移動
log_info "メインリポジトリへ移動..."
cd "$MAIN_REPO"

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

# worktreeの削除（worktree内から実行された場合のみ）
# ブランチ削除より先に行う必要がある
if [ "$IS_WORKTREE" = true ]; then
    log_info "Worktreeを削除中: $CURRENT_DIR"
    git worktree remove "$CURRENT_DIR" 2>/dev/null || {
        log_warn "Worktreeの自動削除に失敗しました。手動で削除してください:"
        log_warn "  git worktree remove $CURRENT_DIR"
    }
fi

# リモートブランチの削除
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    log_info "リモートブランチを削除中: $CURRENT_BRANCH"
    git push origin --delete "$CURRENT_BRANCH" 2>/dev/null || {
        log_warn "リモートブランチの削除に失敗しました（既に削除済みの可能性）"
    }
fi

# ローカルブランチの削除
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    log_info "ローカルブランチを削除中: $CURRENT_BRANCH"
    git branch -d "$CURRENT_BRANCH" 2>/dev/null || {
        log_warn "ローカルブランチの削除に失敗しました（既に削除済みの可能性）"
    }
fi

log_info "クリーンアップ完了"
echo ""
echo "現在の状態:"
git status
