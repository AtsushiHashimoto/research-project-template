#!/usr/bin/env bash
# ============================================================
# テンプレートリポジトリの所在（URL / ブランチ）の単一情報源
# [Template] research-project-template 由来
# ============================================================
#
# `/template-sync` `/template-contribute` と関連スクリプトは、
# テンプレートの URL をハードコードせず**必ずこのスクリプトから取得する**（#122 D3）。
# fork して運用する場合、書き換える場所は `.claude/template-source.json` の1箇所だけになる。
#
# 参照元:
#   .claude/template-source.json   … install.sh が配布時に書き出す。ここが正
#   （不在時）ハードコードの既定値  … 下記 DEFAULT_REPO / DEFAULT_BRANCH
#
# ★ 不在時のフォールバックは「設定の既定値」として承認済み（#122 Fallback ホワイトリスト 1）。
#   既存の派生プロジェクトには当該ファイルが無いため。
#   **ただし黙って落ちない。** 既定値を使ったことを必ず stderr に表示する（R-D01）。
#
# Usage:
#   bash scripts/template-source.sh            # URL を出力（既定）
#   bash scripts/template-source.sh --branch   # ブランチ名を出力
#   bash scripts/template-source.sh --name     # リポジトリ名（fork 検出の grep 用）
#   bash scripts/template-source.sh --json     # 解決結果をまとめて表示
#
# Exit codes:
#   0 正常終了（既定値へのフォールバックを含む）
#   2 引数エラー

set -uo pipefail

# install.sh の TEMPLATE_REPO / TEMPLATE_BRANCH と同じ値。
# install.sh は「配布の起点」なので自分自身をブートストラップできる必要があり、
# 定義を持つのは意図的（#122 D3）。それ以外の読み取り側はここを経由する。
DEFAULT_REPO="https://github.com/AtsushiHashimoto/research-project-template"
DEFAULT_BRANCH="main"

WHAT="repo"
case "${1:-}" in
  "" | --repo) WHAT="repo" ;;
  --branch) WHAT="branch" ;;
  --name) WHAT="name" ;;
  --json) WHAT="json" ;;
  -h | --help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "ERROR: 不明な引数: $1" >&2
    exit 2
    ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SOURCE_FILE="$ROOT/.claude/template-source.json"

# 値の取り出しは sed で行う（jq が無い環境でも動く必要がある）
json_value() {
  # json_value <file> <key>
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1
}

REPO=""
BRANCH=""
ORIGIN="$SOURCE_FILE"

if [ -f "$SOURCE_FILE" ]; then
  REPO=$(json_value "$SOURCE_FILE" repo)
  BRANCH=$(json_value "$SOURCE_FILE" branch)
fi

if [ -z "$REPO" ]; then
  if [ -f "$SOURCE_FILE" ]; then
    echo "⚠️ .claude/template-source.json に repo が入っていません。既定値を使います: $DEFAULT_REPO" >&2
  else
    echo "⚠️ .claude/template-source.json がありません（既存プロジェクトでは未生成）。" >&2
    echo "   ハードコードの既定値を使います: $DEFAULT_REPO" >&2
    echo "   fork を使っている場合は install.sh を再実行するか、次の内容で作成してください:" >&2
    echo "     {\"repo\": \"<fork の URL>\", \"branch\": \"main\"}" >&2
  fi
  REPO="$DEFAULT_REPO"
  ORIGIN="(既定値)"
fi

[ -n "$BRANCH" ] || BRANCH="$DEFAULT_BRANCH"

case "$WHAT" in
  repo) printf '%s\n' "$REPO" ;;
  branch) printf '%s\n' "$BRANCH" ;;
  name) printf '%s\n' "$(basename "${REPO%.git}")" ;;
  json)
    echo "repo   : $REPO"
    echo "branch : $BRANCH"
    echo "name   : $(basename "${REPO%.git}")"
    echo "source : $ORIGIN"
    ;;
esac
exit 0
