#!/usr/bin/env bash
# ============================================================
# worktree の .git 参照を相対パスにする設定
# [Template] research-project-template 由来
# ============================================================
#
# 背景:
#   git worktree add は既定で .git 参照を「絶対パス」で 2 箇所に書き込む。
#     worktrees/issueN/.git        → gitdir: <絶対パス>/.git/worktrees/issueN
#     .git/worktrees/issueN/gitdir → <絶対パス>/worktrees/issueN/.git
#
#   devcontainer はリポジトリを /workspace にマウントするため、ホストとコンテナで
#   絶対パスが一致しない。結果として **worktree を作成した側の環境でしか git / gh が
#   動かない**（双方向に壊れる）。
#
#   worktree.useRelativePaths=true にすると相対パスで書かれ、両環境から解決できる。
#
# 要件:
#   git 2.48 以降（--relative-paths / worktree.useRelativePaths の対応バージョン）
#
# 呼び出し元:
#   - .devcontainer/post-create.sh （コンテナ側）
#   - scripts/init-data.sh         （ホスト側 /worktree-init 経由）

set -uo pipefail

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "[worktree-paths] git リポジトリではないためスキップ"
  exit 0
}

GIT_VERSION=$(git --version | awk '{print $3}')
GIT_MAJOR=${GIT_VERSION%%.*}
GIT_REST=${GIT_VERSION#*.}
GIT_MINOR=${GIT_REST%%.*}

if [ "$GIT_MAJOR" -gt 2 ] || { [ "$GIT_MAJOR" -eq 2 ] && [ "$GIT_MINOR" -ge 48 ]; }; then
  git config worktree.useRelativePaths true
  echo "[worktree-paths] worktree.useRelativePaths=true を設定（git ${GIT_VERSION}）"
else
  echo "[worktree-paths] WARNING: git ${GIT_VERSION} は worktree.useRelativePaths 未対応（2.48 以降が必要）"
  echo "[worktree-paths] ホストと devcontainer で worktree を共有すると git / gh が動きません。"
  echo "[worktree-paths] 各環境で 'git worktree repair' を実行して回避してください。"
fi

# 既存 worktree の絶対パスをこの環境向けに修復する。
# 相対パス化されていない過去の worktree を救済するため、設定の成否に関わらず実行する。
if [ -d "$(git rev-parse --git-common-dir)/worktrees" ]; then
  git worktree repair >/dev/null 2>&1 && echo "[worktree-paths] 既存 worktree の参照を修復しました"
fi

exit 0
