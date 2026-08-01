#!/usr/bin/env bash
# Wrapper for /worktree-init skill
#
# **初期化シーケンスの単一情報源。** install.sh もこのスクリプトを呼ぶ。
# 順序を変える場合はここだけを直すこと（呼び出し側に手順を複製しない）。
#
#   1. configure-worktree-paths.sh … worktree の .git 参照を相対パス化
#   2. setup-labels.sh             … GitHub ラベルのプロビジョニング
#   3. init-data.sh                … データディレクトリの作成

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# worktree の .git 参照を相対パス化（ホスト/コンテナ間でパスが異なるため）
if [ -x "$REPO_ROOT/scripts/configure-worktree-paths.sh" ]; then
  "$REPO_ROOT/scripts/configure-worktree-paths.sh" || true
fi

# GitHub ラベルのプロビジョニング
# gh 未認証・remote 未設定はインストール時点で正常にありうる状態なので、
# 失敗しても初期化全体は止めない。ただし**黙って続行しない**（後で手動実行できるよう案内する）
if [ -x "$REPO_ROOT/scripts/setup-labels.sh" ]; then
  if ! "$REPO_ROOT/scripts/setup-labels.sh"; then
    echo ""
    echo "[WARN] GitHub ラベルの作成に失敗しました（gh 未認証 / remote 未設定など）。"
    echo "       GitHub リポジトリを用意したあと、次を実行してください:"
    echo "         bash scripts/setup-labels.sh"
    echo "       ラベルが無いと /issue-create が前提チェックで停止します。"
    echo ""
  fi
fi

exec "$REPO_ROOT/scripts/init-data.sh" "$@"
