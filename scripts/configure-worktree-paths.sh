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
# 方式:
#   worktree.useRelativePaths / --relative-paths（git 2.48+）は使わない。リポジトリに
#   extensions.relativeWorktrees が書かれ、git < 2.48 の環境がリポジトリを開けなくなるため。
#   新規作成は scripts/worktree-relative.sh add、既存の修復は同 fix が相対化を担う（単一情報源）。
#
# 呼び出し元:
#   - .devcontainer/post-create.sh （コンテナ側）
#   - .claude/skills/worktree-init/init.sh（/worktree-init）

set -uo pipefail
# 終了コード: 0 = 正常（git リポジトリでない場合のスキップを含む）、1 = 異常（握りつぶさない）

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  # .git があるのに解決できない = 別環境で作られた worktree か、古い git では開けない設定
  # （extensions.relativeWorktrees 等）。正常な分岐より静かにしない
  if [ -e .git ]; then
    echo "[worktree-paths] ERROR: .git はあるが、この環境の git から解決できません（git rev-parse で詳細を確認）" >&2
    exit 1
  fi
  echo "[worktree-paths] git リポジトリではないためスキップ"
  exit 0
fi

if [ "$(git config --type=bool --get worktree.useRelativePaths || true)" = true ]; then
  echo "[worktree-paths] WARNING: worktree.useRelativePaths=true は古い git がリポジトリを開けなくなるので解除します" >&2
  git config --unset worktree.useRelativePaths 2>/dev/null || true
  # --global 等、このリポジトリの外で設定されていると上の --unset では消えない
  if [ "$(git config --type=bool --get worktree.useRelativePaths || true)" = true ]; then
    echo "[worktree-paths] ERROR: worktree.useRelativePaths=true が残っています: $(git config --show-origin --get worktree.useRelativePaths)" >&2
    exit 1
  fi
fi

# 既存 worktree を相対化し、メイン側の参照をこの環境向けに修復する。
# 相対パス化されていない過去の worktree を救済するため、設定の成否に関わらず実行する。
if [ -d "$(git rev-parse --git-common-dir)/worktrees" ]; then
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  if ! bash "$SCRIPT_DIR/worktree-relative.sh" fix >/dev/null; then
    echo "[worktree-paths] ERROR: 既存 worktree の修復に失敗（bash scripts/worktree-relative.sh fix で詳細を確認）" >&2
    exit 1
  fi
  echo "[worktree-paths] 既存 worktree の参照を相対化・修復しました"
fi
