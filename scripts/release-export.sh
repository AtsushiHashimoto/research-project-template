#!/usr/bin/env bash
# ============================================================
# 成果物リリース用のクリーンなソースツリーを生成する
# [Template] research-project-template 由来
# ============================================================
#
# `/release` スキルの実体（#102）。
#
# git archive で指定 ref のツリーを展開し、開発ハーネス（テンプレート由来の
# 作業環境ファイル）を除外した tar.gz を生成する。v1.0.0 のような公開成果物に
# `.claude/` や `.spec/` などの開発用ファイルが混入するのを防ぐ。
#
# 既定の除外（＝install.sh が配布する開発ハーネス一式＋テンプレート付属物）:
#   .claude/  .spec/  .dev/  .devcontainer/  worktrees/  scripts/
#   claude-san  install.sh  .gitattributes
#   docs/claude-san.md  docs/devcontainer-internals.md  docs/security.md
#
# ★ 除外・保持は必ず一覧表示する（無言の切り捨て禁止）。
#   プロジェクト固有のファイルが scripts/ 等にある場合は --keep で保持すること。
#
# `docs/surveys/` を除外しない理由（#114 の指摘に対する判断。#122 で記録）:
#   survey は**研究成果物**であり、doc-principles.md でも `docs/` 側（公開ドキュメント）に
#   置くと定めている。開発ハーネス（作業の道具）ではないので成果物に含める。
#   内部開発メモ（ADR・バックログ・設計ノート）は `.dev/` にあり、そちらは除外済み。
#   公開したくない survey がある場合のみ `--exclude docs/surveys` を明示すること。
#
# Usage:
#   bash scripts/release-export.sh --ref v1.0.0 [options]
#
# Options:
#   --ref <ref>       アーカイブ対象の tag / branch / commit（既定: HEAD）
#   --out <file>      出力 tar.gz（既定: <repo名>-<ref>.tar.gz）
#   --keep <path>     既定の除外リストから外す（複数回指定可）
#   --exclude <path>  除外に追加する（複数回指定可）
#   --list            生成せず、除外/保持の一覧だけ表示する
#   -h, --help        使い方を表示
#
# Exit codes:
#   0 正常終了 / 1 引数・環境エラー / 2 アーカイブ生成失敗

set -euo pipefail

DEFAULT_EXCLUDES=(
  ".claude"
  ".spec"
  ".dev"
  ".devcontainer"
  "worktrees"
  "scripts"
  # tests/ は scripts/ を参照する（quality-check.sh 等）。scripts を除外する成果物に
  # 残すと参照切れになる。#121 で CI workflow を除外したのと同じ理由（#135 検証の指摘）
  "tests"
  "claude-san"
  "install.sh"
  # 同梱 CI は scripts/quality-check.sh を実行する開発ハーネス。
  # scripts/ を除外する成果物に残すと参照先の無い workflow になる（#121）
  ".gitattributes"
  "docs/claude-san.md"
  "docs/devcontainer-internals.md"
  "docs/security.md"
)

# 行番号を固定するとヘッダを増やすたびに末尾が切れる（#118・#119 で再発）。
# shebang の次から最初の非コメント行までを出す
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; }

REF="HEAD"
OUT=""
LIST_ONLY=false
KEEPS=()
EXTRA_EXCLUDES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)      REF="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --keep)     KEEPS+=("${2%/}"); shift 2 ;;
    --exclude)  EXTRA_EXCLUDES+=("${2%/}"); shift 2 ;;
    --list)     LIST_ONLY=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "エラー: git リポジトリ内で実行してください" >&2; exit 1; }
cd "$REPO_ROOT"

git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || {
  echo "エラー: ref '$REF' を解決できません" >&2; exit 1; }

REPO_NAME=$(basename "$REPO_ROOT")
SAFE_REF=$(echo "$REF" | tr '/' '-')
[ -n "$OUT" ] || OUT="${REPO_NAME}-${SAFE_REF}.tar.gz"

# 除外リストの確定（--keep で外し、--exclude で足す）
EXCLUDES=()
for e in "${DEFAULT_EXCLUDES[@]}" ${EXTRA_EXCLUDES[@]+"${EXTRA_EXCLUDES[@]}"}; do
  skip=false
  for k in ${KEEPS[@]+"${KEEPS[@]}"}; do
    [ "$e" = "$k" ] && skip=true && break
  done
  [ "$skip" = true ] || EXCLUDES+=("$e")
done

# ref のツリーに実在するものだけを対象にする
tree_files=$(git ls-tree -r --name-only "$REF")

is_excluded() {
  local f="$1" e
  for e in "${EXCLUDES[@]}"; do
    [ "$f" = "$e" ] && return 0
    case "$f" in "$e"/*) return 0 ;; esac
  done
  return 1
}

kept_count=0
excluded_count=0
while IFS= read -r f; do
  if is_excluded "$f"; then
    excluded_count=$((excluded_count + 1))
  else
    kept_count=$((kept_count + 1))
  fi
done <<<"$tree_files"

echo "=== release-export ==="
echo "ref: $REF"
echo "除外（開発ハーネス。${excluded_count} ファイル）:"
for e in "${EXCLUDES[@]}"; do
  if git ls-tree -r --name-only "$REF" -- "$e" 2>/dev/null | grep -q .; then
    echo "  - $e"
  else
    echo "  - $e （ref に存在しないためスキップ）"
  fi
done
echo "保持: ${kept_count} ファイル"
echo ""
echo "★ プロジェクト固有のファイルが除外対象に含まれていないか上の一覧を確認すること。"
echo "  保持したい場合: --keep <path>"

if [ "$LIST_ONLY" = true ]; then
  exit 0
fi

# 展開 → 除外削除 → 再圧縮（git archive は除外 pathspec を持たないため）
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="${REPO_NAME}-${SAFE_REF}"
git archive --format=tar --prefix="$PREFIX/" "$REF" | tar -x -C "$TMP" || {
  echo "エラー: git archive に失敗しました" >&2; exit 2; }

for e in "${EXCLUDES[@]}"; do
  rm -rf "${TMP:?}/$PREFIX/$e"
done

# 除外で空になったディレクトリを掃除
find "$TMP/$PREFIX" -type d -empty -delete 2>/dev/null || true

tar -czf "$OUT" -C "$TMP" "$PREFIX" || {
  echo "エラー: tar 生成に失敗しました" >&2; exit 2; }

echo ""
echo "生成: $OUT"
echo "検証（開発ハーネスが含まれていないこと）:"
if tar -tzf "$OUT" | grep -E "/(\.claude|\.spec|\.dev|\.devcontainer|worktrees)/" | head -5 | grep -q .; then
  # --keep で意図的に残した場合のみここに来る
  echo "  ⚠ 開発ハーネスのパスが含まれています（--keep 指定を確認）"
else
  echo "  ✅ .claude / .spec / .dev / .devcontainer / worktrees は含まれていません"
fi
