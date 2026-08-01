#!/usr/bin/env bash
# Wrapper for /worktree-init skill
#
# **初期化シーケンスの単一情報源。** install.sh もこのスクリプトを呼ぶ。
# 順序を変える場合はここだけを直すこと（呼び出し側に手順を複製しない）。
#
#   1. configure-worktree-paths.sh … worktree の .git 参照を相対パス化
#   2. setup-labels.sh             … GitHub ラベルのプロビジョニング
#   3. init-data.sh                … データディレクトリの作成

# --root <dir> で対象を明示できる（install.sh から呼ぶときに使う）。
# 省略時は git のトップレベル、それも無ければカレント。
# ★ 明示指定が必要な理由: git リポジトリのサブディレクトリを対象にする場合、
#   git rev-parse は外側のリポジトリを指してしまい、scripts/ を見つけられない
if [ "${1:-}" = "--root" ] && [ -n "${2:-}" ]; then
  REPO_ROOT="$2"
  shift 2
else
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

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
