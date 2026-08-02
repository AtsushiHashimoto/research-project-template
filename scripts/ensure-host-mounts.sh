#!/usr/bin/env bash
# ============================================================
# bind mount 元（ホスト側）の存在を保証する
# [Template] research-project-template 由来
# ============================================================
#
# `.devcontainer/docker-compose.yml` は次の2つをホストから bind mount する:
#   ${HOME}/.gitconfig     → /home/vscode/.gitconfig
#   ${HOME}/.config/gh     → /home/vscode/.config/gh
#
# **存在確認をせずにマウントすると壊れる**（#122 M）。
# Docker はマウント元が無い場合に**ディレクトリとして自動作成**するため、
#   - `~/.gitconfig` がディレクトリになり、以後ホストの git が
#     "fatal: ... is a directory" で動かなくなる
#   - コンテナ内の git / gh も設定を読めない
# という、後から原因を追いにくい壊れ方をする。
#
# devcontainer.json の `initializeCommand`（ホスト側で、コンテナ作成前に走る）から
# 呼び、不足していれば**正しい種別で**作ってからマウントさせる。
#
# 何も勝手に上書きしない。作成するのは「存在しないとき」だけで、内容は空。
#
# Usage:
#   bash scripts/ensure-host-mounts.sh [--help]
#
# Exit codes:
#   0  処理を実行した（問題があっても devcontainer の起動は止めない。警告で知らせる）
#   1  引数エラー（--help 以外の引数を渡した場合のみ）

set -uo pipefail

case "${1:-}" in
  -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
  "") ;;
  *) echo "不明な引数: $1（引数は取りません）" >&2; exit 1 ;;
esac

HOME_DIR="${HOME:-}"
if [ -z "$HOME_DIR" ]; then
  echo "[host-mounts] WARNING: HOME が未設定のため確認できません" >&2
  exit 0
fi

status=0

ensure_file() {
  local path="$1"
  if [ -f "$path" ]; then
    echo "[host-mounts] OK  (file) $path"
  elif [ -e "$path" ]; then
    # 既にディレクトリ等になっている＝過去に Docker が作ってしまった状態。
    # 勝手に消すと利用者のデータを壊しうるので、**直し方を必ず表示する**（黙って進めない）。
    # ただし devcontainer の起動自体は止めない（ここで止めると作業が始められない）
    echo "[host-mounts] WARNING: ${path} はファイルではありません（ディレクトリ等）" >&2
    echo "[host-mounts]   Docker が bind mount 時に自動作成した可能性があります。" >&2
    echo "[host-mounts]   中身を確認し、不要なら削除してから再度コンテナを起動してください:" >&2
    echo "[host-mounts]     rm -rf '$path' && touch '$path'" >&2
    status=1
  else
    : >"$path" && echo "[host-mounts] 作成 (file) ${path}（空。マウント先がディレクトリ化するのを防ぐため）"
  fi
}

ensure_dir() {
  local path="$1"
  if [ -d "$path" ]; then
    echo "[host-mounts] OK  (dir)  $path"
  elif [ -e "$path" ]; then
    echo "[host-mounts] WARNING: ${path} はディレクトリではありません" >&2
    status=1
  else
    mkdir -p "$path" && echo "[host-mounts] 作成 (dir)  $path"
  fi
}

ensure_file "$HOME_DIR/.gitconfig"
ensure_dir "$HOME_DIR/.config/gh"

if [ "$status" -ne 0 ]; then
  echo "[host-mounts] 上の警告を解消しないと、コンテナ内の git / gh が正しく動きません" >&2
fi

# 起動は止めない（マウント自体は Docker が行う）。警告は必ず表示済み
exit 0
