#!/usr/bin/env bash
# ============================================================
# スキルが使うラベルの定義済み検証
# [Template] research-project-template 由来
# ============================================================
#
# `.claude/skills/**` が `gh issue create --label X` 等で使うラベルが
# `scripts/setup-labels.sh` に定義済みかを検査する（#118）。
#
# 背景: 未定義ラベルを渡すと gh は 422 で失敗するため、当該ステップが必ず落ちる。
# Integrity Review #114 C3 では5種の未定義ラベルが使われており、
# レビュー報告 issue の投稿自体がラベル無しを強いられた。
#
# 検査対象の記法:
#   --label "X"      --label X
#   --add-label X    --remove-label X
#
# 除外:
#   - コメント行（`#` で始まる行）
#   - シェル変数（`$VAR` / `${VAR}` を含む値）… 静的には解決できない
#   - `skill-labels:allow` を含む行
#   ※ `{a|b|c}` 形式は**除外せず** `|` で分割して各候補を照合する。
#     一律除外すると「候補の1つだけが未定義」という形の退行
#     （#114 の `{bug|refactor|test}` がまさにこれ）を見逃す
#
# 除外件数は必ず表示する（無言の切り捨て禁止）。
#
# Usage:
#   bash scripts/check-skill-labels.sh [--help]
#
# Exit codes:
#   0 問題なし（または対象が無くスキップ）
#   1 未定義ラベルの使用を検出

set -uo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

[ -d .claude/skills ] || { echo "[skill-labels] .claude/skills が無いためスキップ"; exit 0; }
[ -f scripts/setup-labels.sh ] || {
  echo "[skill-labels] scripts/setup-labels.sh が無いためスキップ"; exit 0; }

# --- 定義済みラベル（setup-labels.sh の LABELS 配列が単一情報源）---
DEFINED=$(grep -oE '^[[:space:]]*"[a-z][a-z-]*\|[0-9A-Fa-f]{6}\|' scripts/setup-labels.sh \
          | sed 's/.*"//; s/|.*//' | sort -u)
[ -n "$DEFINED" ] || { echo "[skill-labels] ラベル定義を読めませんでした"; exit 1; }

FILES=()
while IFS= read -r f; do [ -f "$f" ] && FILES+=("$f"); done < <(git ls-files '.claude/skills/*')
[ "${#FILES[@]}" -gt 0 ] || { echo "[skill-labels] 走査対象がありません"; exit 0; }

EXCLUDED=0
FOUND=0
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

for f in "${FILES[@]}"; do
  # コメント行と除外マーカー行を落とす。
  # 件数は「ラベル指定を含むのに除外した行」だけを数える（全コメント行を数えても意味がない）
  while IFS= read -r line; do
    case "$line" in
      \#*|*skill-labels:allow*)
        case "$line" in
          *--label*|*--add-label*|*--remove-label*) EXCLUDED=$((EXCLUDED + 1)) ;;
        esac
        continue ;;
    esac
    # ラベル指定を抽出（クォート有無の両方）
    printf '%s\n' "$line" \
      | grep -oE -- '--(add-|remove-)?label[= ]+"[^"]+"|--(add-|remove-)?label[= ]+[A-Za-z0-9{}|_-]+' \
      | sed -E 's/^--(add-|remove-)?label[= ]+//; s/^"//; s/"$//' \
      | while IFS= read -r val; do
          case "$val" in
            *'$'*) continue ;;                     # シェル変数は静的に解決できない
          esac
          # {a|b|c} 形式は分割して各候補を見る
          val="${val#\{}"; val="${val%\}}"
          printf '%s\n' "$val" | tr ',|' '\n\n' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
            | while IFS= read -r one; do
                [ -n "$one" ] || continue
                case "$one" in *'$'*|*'{'*|*'}'*) continue ;; esac
                printf '%s\t%s\n' "$one" "$f" >>"$TMP"
              done
        done
  done < "$f"
done

# 未定義ラベルの検出
if [ -s "$TMP" ]; then
  while IFS=$'\t' read -r label file; do
    if ! printf '%s\n' "$DEFINED" | grep -qx -- "$label"; then
      echo "[skill-labels] 未定義ラベル '${label}' の使用: ${file}"
      grep -n -- "$label" "$file" | head -2 | sed 's/^/    /'
      FOUND=1
    fi
  done < <(sort -u "$TMP")
fi

echo "[skill-labels] 除外行: ${EXCLUDED} 行（コメント / 'skill-labels:allow'）"

# --- labels.md と setup-labels.sh の説明文が食い違っていないか ---
# 両方を手で更新する運用（labels.md 冒頭の宣言）を機械で担保する。
# GitHub 上に表示されるのはスクリプト側の文言なので、そちらを正とする。
# 比較時は Markdown の装飾（** と `）だけ落として本文を突き合わせる
LABELS_MD=".claude/rules/template/labels.md"
if [ ! -f "$LABELS_MD" ]; then
  echo "[skill-labels] 説明文の一致検査はスキップ（${LABELS_MD} が無い）"
else
  while IFS='|' read -r name _color desc; do
    [ -n "$name" ] || continue
    row=$(grep -m1 -F "| \`${name}\` |" "$LABELS_MD" || true)
    if [ -z "$row" ]; then
      echo "[skill-labels] labels.md に行がありません: ${name}"
      FOUND=1
      continue
    fi
    # 「用途」列＝3フィールド目を取る（表は 2列/3列 の両方がある）。
    # Markdown ではセル内の `|` は `\|` とエスケープするのが正なので、
    # 分割後にアンエスケープして比較する（`|` 入りの説明文でも一致させられる）
    # エスケープ済み `\|` はセル区切りではないので、分割前に退避して後で戻す
    md_desc=$(printf '%s' "$row" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' '{print $3}' \
              | sed 's/@@PIPE@@/|/g; s/^[[:space:]]*//; s/[[:space:]]*$//; s/\*\*//g; s/`//g')
    sh_desc=$(printf '%s' "$desc" \
              | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/\*\*//g; s/`//g')
    if [ "$md_desc" != "$sh_desc" ]; then
      echo "[skill-labels] 説明文の不一致: ${name}"
      echo "    setup-labels.sh: ${sh_desc}"
      echo "    labels.md      : ${md_desc}"
      FOUND=1
    fi
  done < <(grep -oE '^[[:space:]]*"[a-z][a-z-]*\|[0-9A-Fa-f]{6}\|[^"]*"' scripts/setup-labels.sh \
           | sed 's/^[[:space:]]*"//; s/"$//')
fi

if [ "$FOUND" -ne 0 ]; then
  echo "[skill-labels] 定義済みラベル（scripts/setup-labels.sh が単一情報源）:"
  printf '%s\n' "$DEFINED" | sed 's/^/  /'
  echo "[skill-labels] ラベルを増やす場合は setup-labels.sh と"
  echo "               .claude/rules/template/labels.md の両方を更新すること。"
  exit 1
fi

echo "[skill-labels] スキルが使うラベルは全て定義済みです"
exit 0
