#!/usr/bin/env bash
# ============================================================
# スキル参照名の実在検証
# [Template] research-project-template 由来
# ============================================================
#
# ドキュメント・スクリプトが参照するスキル名が `.claude/skills/` に実在するかを検査する（#117）。
#
# 背景: スキルを一斉リネーム（スラッシュ区切り → ハイフン区切り）した際に参照側が追従せず、
# `/commit` ルータの全分岐や `issue-finish` の委譲先など**実行経路が死んでいた**
# （Integrity Review #114 C2、約200箇所）。人手の grep では再発を防げないため機械化する。
#
# 検出するもの:
#   1. 旧スラッシュ表記（`/commit/merge`, `Skill(skill="issue/unblock")` など） skill-refs:allow
#      … 実在スキル名から機械生成したペアだけを見るので、ファイルパスと誤認しない
#   2. リネーム済みの旧名（/issue-auto, /issue-cycle, /start-task, /finish-task） skill-refs:allow
#   3. `Skill(skill="...")` が指すスキルの不在
#
# 除外（当時の実行記録であり、書き換えると履歴が壊れる）:
#   .spec/issues/  docs/surveys/  data/shared/integrity-reviews/
#
# 行単位の除外（正当に旧名を書く必要がある箇所）:
#   - `（旧 ...）` / `(旧 ...)` … リネームの移行導線。ユーザーに旧名を示すのが目的
#   - `skill-refs:allow` を含む行 … 旧名を意図的に書く箇所（本スクリプトの定義行など）
#
# Usage:
#   bash scripts/check-skill-references.sh [--help]
#
# Exit codes:
#   0 問題なし（または .claude/skills が無くスキップ）
#   1 参照切れを検出

set -uo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

[ -d .claude/skills ] || { echo "[skill-refs] .claude/skills が無いためスキップ"; exit 0; }

FOUND=0

# 走査対象（除外範囲を適用）
targets() {
  git ls-files \
    | grep -vE '^\.spec/issues/' \
    | grep -vE '^docs/surveys/' \
    | grep -vE '^data/shared/integrity-reviews/' \
    | grep -E '\.(md|sh|json)$|^claude-san$|^install\.sh$|^setup\.sh$'
}

FILES=()
while IFS= read -r f; do [ -f "$f" ] && FILES+=("$f"); done < <(targets)
[ "${#FILES[@]}" -gt 0 ] || { echo "[skill-refs] 走査対象がありません"; exit 0; }

# --- 1. 実在スキル名から旧スラッシュ形を生成して探す ---
# 左境界: 直前が [A-Za-z0-9_.-] でない（先頭スラッシュは許す＝スキル呼び出しの記法）
# 右境界: 直後が [a-z/-] でない（より長い名前・パスの一部を壊さない）
while IFS= read -r name; do
  case "$name" in
    *-*) OLD="${name%%-*}/${name#*-}" ;;
    *) continue ;;
  esac
  hits=$(OLD="$OLD" perl -ne \
    'print "$ARGV:$.: $_"
       if !/skill-refs:allow/ && !/[（(]旧/
       && m{(?<![A-Za-z0-9_.-])\Q$ENV{OLD}\E(?![a-z/-])};
     close ARGV if eof;' \
    "${FILES[@]}" 2>/dev/null)
  if [ -n "$hits" ]; then
    # 全角括弧が変数名の一部として解釈されるため ${} で明示的に閉じる
    echo "[skill-refs] 旧表記 '${OLD}'（正: ${name}）:"
    echo "$hits" | sed 's/^/  /'
    FOUND=1
  fi
done < <(ls .claude/skills)

# --- 2. リネーム済みの旧名 ---
for pair in "issue-auto|task-run" "issue-cycle|epic-cycle" "start-task|task-start" "finish-task|issue-finish"; do  # skill-refs:allow
  OLD="${pair%%|*}"; new="${pair##*|}"
  hits=$(OLD="$OLD" perl -ne \
    'print "$ARGV:$.: $_"
       if !/skill-refs:allow/ && !/[（(]旧/
       && m{(?<![A-Za-z0-9_.-])\Q$ENV{OLD}\E(?![a-z/-])};
     close ARGV if eof;' \
    "${FILES[@]}" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "[skill-refs] 旧名 '${OLD}'（正: ${new}）:"
    echo "$hits" | sed 's/^/  /'
    FOUND=1
  fi
done

# --- 3. Skill(skill="...") の指す先が実在するか ---
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if [ ! -d ".claude/skills/$ref" ]; then
    echo "[skill-refs] 実在しないスキルへの呼び出し: Skill(skill=\"$ref\")"
    grep -rn "skill=\"$ref\"" .claude scripts 2>/dev/null | sed 's/^/  /' | head -5
    FOUND=1
  fi
done < <(
  # 除外マーカーの付いた行を落としてから抽出する。               skill-refs:allow
  # 呼び出しの2形式を見る（属性形とパラメータタグ形）             skill-refs:allow
  grep -h -v 'skill-refs:allow' "${FILES[@]}" 2>/dev/null \
    | grep -oE '<parameter name="skill">[A-Za-z0-9/_-]+|skill="[A-Za-z0-9/_-]+"' \
    | sed -e 's|<parameter name="skill">||' -e 's|^skill="||' -e 's|"$||' \
    | sort -u
)

if [ "$FOUND" -ne 0 ]; then
  echo "[skill-refs] 参照切れを検出しました。実在するスキル名（ハイフン区切り）に修正してください:"
  ls .claude/skills | sed 's/^/  \//'
  exit 1
fi

echo "[skill-refs] スキル参照名は全て実在します"
exit 0
