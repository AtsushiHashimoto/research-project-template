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
  # 失敗しても作成は続ける。ただし捨てずに知らせる（理由はスクリプト自身が stderr に出す）
  ./scripts/configure-worktree-paths.sh \
    || echo "[post-create] WARNING: configure-worktree-paths.sh が失敗した（理由は直前の ERROR 行。bash scripts/worktree-relative.sh fix で再確認）" >&2
fi

# 共通スキルの参照とセッション文脈フック（失敗を最終判定へ反映）
if [ -f scripts/configure-agent-workflow.sh ]; then
  if ! bash scripts/configure-agent-workflow.sh; then claude_fail=1; fi
fi

# Claude Code native build（#151）
# ~/.claude の chown と ~/.claude.json の symlink の後に置く（インストーラが ~/.claude.json に書くため）。
# 失敗は記録して続行し、最後に非ゼロ終了する（[Project] 部分を巻き込まない）
if ! bash .devcontainer/install-claude-native.sh; then
  claude_fail=1
fi

# PATH 上で実際に起動する claude の版を確かめる
#   導入が「ok」でも、PATH の先に古い npm 版などが居ると古い claude が起動する（下流で実際に起きた）。
#   下限は install-claude-native.sh の MIN_VERSION_DEFAULT から読む（書き写すと上げたときに古いまま緑になる）。
#   行全体の形を検証し、崩れていたら空になって下で明示的に落ちる。パイプと早期終了する読み手は使わない。
claude_min=$(awk -F= '/^MIN_VERSION_DEFAULT=[0-9.]+$/{print $2; exit}' .devcontainer/install-claude-native.sh)
if [ -z "$claude_min" ]; then
  echo "[post-create:claude-path] FAIL: install-claude-native.sh から下限を読めなかった（MIN_VERSION_DEFAULT の行が変わった？）" >&2
  claude_fail=1
elif resolved=$(command -v claude 2>/dev/null); then
  rv=$(grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$("$resolved" --version 2>&1)" || true)
  if [ -z "$rv" ]; then
    echo "[post-create:claude-path] WARN: PATH 上の $resolved の版を読めなかった" >&2
  elif [ "$(printf '%s\n%s\n' "$claude_min" "$rv" | sort -V | sed -n '1p')" != "$claude_min" ]; then
    echo "[post-create:claude-path] FAIL: PATH 上の claude は $resolved の $rv で、下限 $claude_min 未満" >&2
    echo "[post-create:claude-path] PATH の先頭に ~/.local/bin があるか、古い npm 版が残っていないかを見ること（sudo npm -g uninstall @anthropic-ai/claude-code）" >&2
    claude_fail=1
  else
    echo "[post-create:claude-path] ok (PATH 上の claude は $resolved の $rv)"
  fi
else
  echo "[post-create:claude-path] FAIL: PATH 上に claude が無い" >&2
  claude_fail=1
fi

# --- [Project] プロジェクト固有の post-create 処理は、この行より下・下の claude_fail 判定より上に追記 ---

# claude 導入の失敗を最後に明示する（まとめは EXIT trap が出す）
if [ "$claude_fail" = 1 ]; then
  exit 1
fi
