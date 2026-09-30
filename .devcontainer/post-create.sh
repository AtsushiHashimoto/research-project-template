#!/usr/bin/env bash
# ============================================================
# Common post-create setup (shared between CPU and GPU)
# [Template] research-project-template 由来
# ============================================================
set -e

# claude 導入の失敗の記録（#151）。失敗は握りつぶさず、後続を実行したうえで最後に非ゼロ終了する。
# 途中の別処理が set -e で止まった場合も、EXIT 時に claude の失敗をまとめて出す
# （trap は報告だけで、終了コードは書き換えない）
claude_fail=0
report_claude_fail() {
  if [ "$claude_fail" = 1 ]; then
    echo "[post-create:claude] FAIL: Claude Code native build の導入に失敗した（詳細は上の [post-create:claude] 行）" >&2
    echo "[post-create:claude] 手動で再実行: bash .devcontainer/install-claude-native.sh（post-create 全体なら bash .devcontainer/post-create.sh <name> の後に bash .devcontainer/post-start.sh）" >&2
  fi
  # 明示的に 0 を返す。無いと関数の終了コードが最後の [ ] の偽（1）になり、trap 内の set -e で
  # 正常終了（exit 0）が 1 に化ける（失敗の報告だけが役目で、終了コードは書き換えない）
  return 0
}
trap report_claude_fail EXIT

PROJECT_NAME=${1:-$(basename "$(pwd)")}

# Claude Code config ownership
sudo chown -R "$(id -u):$(id -g)" /home/vscode/.claude

# Symlink for claude settings
ln -sf /home/vscode/.claude/.claude.json /home/vscode/.claude.json

# Deterministic machine-id (per project)
echo -n "devcontainer-${PROJECT_NAME}" | md5sum | cut -c1-32 | sudo tee /etc/machine-id > /dev/null

# TZ environment variable (claude-auto-retry がレート制限の再開時刻をパースするために必要)
# ホストの TZ が未設定の場合、/etc/timezone から fallback
if [ -z "$TZ" ] && [ -f /etc/timezone ]; then
  TZ=$(cat /etc/timezone)
  echo "export TZ='${TZ}'" | sudo tee /etc/profile.d/tz.sh > /dev/null
  echo "TZ set from /etc/timezone: $TZ"
fi

# claude-auto-retry (レート制限自動リトライ)
# 旧 Dockerfile の alias が残っている場合は除去（claude() 関数と競合するため）
sudo sed -i '/alias claude=/d' /etc/bash.bashrc 2>/dev/null || true

if ! command -v claude-auto-retry &> /dev/null; then
  sudo npm i -g claude-auto-retry
fi
# Note: claude-auto-retry install は postStartCommand (post-start.sh) で実行
# （postCreateCommand 時点では .bashrc が updateRemoteUserUID により上書きされる可能性があるため）

# claude-san symlink
# claude-san はテンプレート付属のランチャで、install.sh 経由の派生プロジェクトには
# 配布されない。存在しないまま ln -sf すると壊れた symlink が無言で作られるためガードする
if [ -f "$(pwd)/claude-san" ]; then
  sudo ln -sf "$(pwd)/claude-san" /usr/local/bin/claude-san
fi

# worktree の .git 参照を相対パス化（ホスト/コンテナ間でパスが異なるため）
if [ -x ./scripts/configure-worktree-paths.sh ]; then
  ./scripts/configure-worktree-paths.sh || true
fi

# Claude Code native build（#151）
# ~/.claude の chown と ~/.claude.json の symlink の後に置く（インストーラが ~/.claude.json に書くため）。
# 失敗は記録して続行し、最後に非ゼロ終了する（[Project] 部分を巻き込まない）
if ! bash .devcontainer/install-claude-native.sh; then
  claude_fail=1
fi

# --- [Project] プロジェクト固有の post-create 処理は、この行より下・下の claude_fail 判定より上に追記 ---

# claude 導入の失敗を最後に明示する（まとめは EXIT trap が出す）
if [ "$claude_fail" = 1 ]; then
  exit 1
fi
