#!/usr/bin/env bash
# ============================================================
# ワークフローに必須の .gitignore エントリの単一情報源
# [Template] research-project-template 由来
# ============================================================
#
# テンプレートのワークフローが壊れないために**必ず必要な**エントリだけを持つ（#122 O）。
# 言語・エディタ由来の一般的な無視設定はテンプレートの `.gitignore` 側にあり、
# ここでは扱わない（プロジェクトが自由に削れてよいものだから）。
#
# 以前は install.sh だけがこの一覧を持っていたため、
# `/template-sync` にも `/template-contribute` にも .gitignore の経路が無く、
# **テンプレート側でエントリが増えても既存プロジェクトに永久に届かなかった**。
# 一覧をここに集約し、install / sync の双方から呼ぶことで非対称を解消する。
#
# 追加は**追記のみ**。既存行の削除・並べ替えはしない（プロジェクトの編集を壊さないため）。
#
# Usage:
#   bash scripts/ensure-gitignore.sh [--root <dir>] [--check]
#
# Options:
#   --root <dir>  対象プロジェクト。既定はカレントの git リポジトリルート
#   --check       追記せず、不足しているエントリを報告する（不足があれば exit 1）
#
# Exit codes:
#   0  過不足なし / 追記完了
#   1  --check で不足あり、または .gitignore が無い
#   2  引数エラー

set -uo pipefail

# ★ 増減させる場合はテンプレートの `.gitignore` 本体も同時に更新すること
REQUIRED_ENTRIES=(
  # worktrees/ はドット無し（.claude/rules/template/issue-hierarchy.md の規約に一致させる）
  "worktrees/"
  # data/shared 自体を無視する（`/**` だと symlink 化したパス自体が露出し、
  # `git add .` でホスト絶対パスを含む symlink がコミットされる）。#133
  "data/shared"
  "data/local/"
  # /template-sync が退避したローカル改変（還流候補。コミットはしない）
  ".claude/rules/template.bak-*/"
  # resolve-model.sh --disable/--enable の書き込み先（個人・一時的な設定）
  ".claude/model-policy.local.json"
  # `devcontainer up` が自動生成する feature のロックファイル（#140 D5）。
  # feature の版は固定しない方針なのでコミットしない。無視しないと毎回 git status が
  # 汚れ、/template-contribute の偽の還流候補になる（#122 と同種）
  "devcontainer-lock.json"
)

ROOT=""
CHECK_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ -n "${2:-}" ] || { echo "ERROR: --root には値が必要です" >&2; exit 2; }
      ROOT="$2"; shift 2 ;;
    --check) CHECK_ONLY=true; shift ;;
    -h | --help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: 不明な引数: $1" >&2; exit 2 ;;
  esac
done

[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GITIGNORE="$ROOT/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
  echo "[gitignore] $GITIGNORE がありません（テンプレートの .gitignore をコピーしてください）" >&2
  exit 1
fi

MISSING=""
for entry in "${REQUIRED_ENTRIES[@]}"; do
  grep -qxF "$entry" "$GITIGNORE" || MISSING="${MISSING}${entry}"$'\n'
done

if [ -z "$MISSING" ]; then
  echo "[gitignore] 必須エントリは揃っています（${#REQUIRED_ENTRIES[@]} 件）"
  exit 0
fi

if [ "$CHECK_ONLY" = true ]; then
  echo "[gitignore] 不足しているエントリ:"
  printf '%s' "$MISSING" | sed 's/^/  - /'
  echo "  → 追記: bash scripts/ensure-gitignore.sh"
  exit 1
fi

printf '%s' "$MISSING" | while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  echo "$entry" >>"$GITIGNORE"
done
echo "[gitignore] 不足していたエントリを追記しました:"
printf '%s' "$MISSING" | sed 's/^/  + /'
exit 0
