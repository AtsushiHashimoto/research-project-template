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
# gh 未認証・remote 未設定はインストール時点で正常にありうる状態なので、初期化全体は止めない。
# 案内メッセージは setup-labels.sh 自身が出す（終了コード 2 = スキップ、要ユーザー対応）
if [ -x "$REPO_ROOT/scripts/setup-labels.sh" ]; then
  "$REPO_ROOT/scripts/setup-labels.sh"
  labels_rc=$?
  if [ "$labels_rc" -ne 0 ]; then
    echo "[init] ラベル作成は未完了です（上の案内を参照）。初期化は続行します。"
  fi
fi

exec "$REPO_ROOT/scripts/init-data.sh" "$@"
