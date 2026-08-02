#!/usr/bin/env bash
# ============================================================
# QA データディレクトリの解決（シェル側の入口）
# [Template] research-project-template 由来
# ============================================================
#
# **既定値の単一情報源は `scripts/qa/config.py`**（`DEFAULT_QA_DIR` / `LEGACY_QA_DIR`）。
# ここでは値を読み出すだけで、独自の既定値を持たない（#122 D2）。
#
# 解決順:
#   1. `.claude/qa-config.yaml` の `qa_dir:`
#   2. config.py の DEFAULT_QA_DIR
#
# 旧パス（`docs/qa`）にデータが残っている場合は**必ず stderr に案内を出す**。
# 黙って新パスだけを見ると、既存の QA ログが無言で無視される（R-D01 の silent-wrong）。
# 自動移動はしない（ユーザーデータのため）。
#
# Usage:
#   QA_DIR=$(bash scripts/qa/qa-dir.sh)      # 解決結果を stdout に1行
#   bash scripts/qa/qa-dir.sh --check        # 解決結果と旧パスの状態を表示
#
# Exit codes:
#   0  解決できた
#   1  既定値を config.py から読み出せなかった（構成の破損。黙って既定に落ちない）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

CHECK=false
case "${1:-}" in
  "") ;;
  --check) CHECK=true ;;
  -h | --help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "ERROR: 不明な引数: $1" >&2; exit 1 ;;
esac

py_const() {
  # py_const <NAME> — config.py のモジュール定数を読み出す
  sed -n "s/^$1 = \"\\(.*\\)\"$/\\1/p" "$SCRIPT_DIR/config.py" | head -1
}

DEFAULT_QA_DIR=$(py_const DEFAULT_QA_DIR)
LEGACY_QA_DIR=$(py_const LEGACY_QA_DIR)

if [ -z "$DEFAULT_QA_DIR" ] || [ -z "$LEGACY_QA_DIR" ]; then
  echo "ERROR: scripts/qa/config.py から既定パスを読み出せませんでした" >&2
  echo "  DEFAULT_QA_DIR / LEGACY_QA_DIR の定義を確認してください。" >&2
  exit 1
fi

QA_CONFIG="$ROOT/.claude/qa-config.yaml"
QA_DIR=""
if [ -f "$QA_CONFIG" ]; then
  QA_DIR=$(sed -n 's/^[[:space:]]*qa_dir:[[:space:]]*"\{0,1\}\([^"#]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    "$QA_CONFIG" | head -1)
  QA_DIR="${QA_DIR%"${QA_DIR##*[![:space:]]}"}"
fi
[ -n "$QA_DIR" ] || QA_DIR="$DEFAULT_QA_DIR"

# --- 旧パスの検出（loud に案内。自動移動はしない） ---
legacy_has_data=false
if [ "$QA_DIR" != "$LEGACY_QA_DIR" ]; then
  for f in "$ROOT/$LEGACY_QA_DIR/questions.jsonl" "$ROOT/$LEGACY_QA_DIR/answers.jsonl"; do
    [ -s "$f" ] && legacy_has_data=true
  done
fi

if [ "$legacy_has_data" = true ]; then
  {
    echo "[QA] 旧パスにデータが残っています: $LEGACY_QA_DIR/"
    echo "[QA] 現在の参照先は '$QA_DIR' です。旧データは読み込まれません。"
    echo "[QA] 移行するには次を実行してください（自動では移動しません）:"
    echo "[QA]   mkdir -p $QA_DIR && git mv $LEGACY_QA_DIR/*.jsonl $QA_DIR/"
    echo "[QA] 旧パスを使い続ける場合は .claude/qa-config.yaml に 'qa_dir: $LEGACY_QA_DIR' を明示してください。"
  } >&2
fi

if [ "$CHECK" = true ]; then
  echo "qa_dir : $QA_DIR"
  # ★ 変数展開の直後に全角文字を置かないこと。bash 3.2（macOS 標準）は
  #   マルチバイトの先頭バイトを変数名の一部として読み、set -u 下で
  #   "unbound variable" になる。必ず ${VAR} と括ること
  echo "legacy : ${LEGACY_QA_DIR}（データ: $([ "$legacy_has_data" = true ] && echo あり || echo なし)）"
  exit 0
fi

printf '%s\n' "$QA_DIR"
exit 0
