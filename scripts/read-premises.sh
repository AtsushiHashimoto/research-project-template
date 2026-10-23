#!/usr/bin/env bash
# read-premises.sh — ユーザー確定の前提（2層）を1つのテキストとして出力する（.claude/rules/template/premises.md）
#
#   bash scripts/read-premises.sh <issue番号>      # issue / task / epic のどれでも。親を辿り、祖先の epic すべて（sub-epic が先）の前提を出す
#   bash scripts/read-premises.sh --no-epic        # プロジェクト大前提のみ
#   bash scripts/read-premises.sh --epic-only <issue番号>  # epic 前提のみ（大前提が import 済みのセッション向け。session-context.sh が使う）
#   bash scripts/read-premises.sh --epic-body-file F  # epic 本文をファイルから（テスト用。gh を呼ばない）
#
# 出力: 「## プロジェクト大前提」＋「## epic #N の前提」を原文で。サブエージェント prompt にそのまま貼る。
# 終了コード: 0=取得できた（未記入・epic なしは警告を stderr に出して 0）/ 1=gh 失敗・引数不正（黙って続行しない）
set -euo pipefail

INVARIANTS="${PREMISES_INVARIANTS:-.spec/invariants.md}"
PROJECT_HEADING='## ★ プロジェクト大前提（ユーザー確定事項）'
EPIC_HEADING='## 前提（ユーザー確定事項）'

# extract_section <見出し行> : stdin から、見出し行に完全一致する節を次の同レベル以上の見出しまで切り出す。
# CRLF を除去し、``` 内の見出しでは切らない。
extract_section() {
  awk -v h="$1" '
    { sub(/\r$/, "") }
    /^```/ { if (f) { fence = !fence; print; next } }
    f && !fence && /^#{1,2} / { exit }
    $0 == h { f = 1 }
    f { print }
  '
}

# is_blank_section : 見出し以外が空行・HTML コメント・<雛形> だけなら真（＝未記入）
is_blank_section() {
  sed 1d | awk '
    /<!--/ { c = 1 } c { if (/-->/) c = 0; next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*<[^>]*>[[:space:]]*$/ { next }
    /^[[:space:]]*（未記入）[[:space:]]*$/ { next }
    { found = 1 } END { exit found ? 1 : 0 }
  '
}

emit_project() {
  if [ ! -f "$INVARIANTS" ]; then
    echo "WARN: $INVARIANTS が無い（プロジェクト大前提なし）" >&2
    printf '%s\n\n（%s が無い）\n' "$PROJECT_HEADING" "$INVARIANTS"; return
  fi
  local sec; sec=$(extract_section "$PROJECT_HEADING" < "$INVARIANTS")
  if [ -z "$sec" ]; then
    echo "WARN: $INVARIANTS に「${PROJECT_HEADING#\#\# }」節が無い（移行手順: premises-migration.md）" >&2
    printf '%s\n\n（節なし）\n' "$PROJECT_HEADING"; return
  fi
  printf '%s\n' "$sec" | is_blank_section && echo "WARN: プロジェクト大前提が未記入" >&2
  printf '%s\n' "$sec"
}

emit_epic_body() {  # <epic番号 or ラベル> <本文>
  local sec; sec=$(printf '%s\n' "$2" | extract_section "$EPIC_HEADING")
  echo
  if [ -z "$sec" ] || printf '%s\n' "$sec" | is_blank_section; then
    echo "WARN: epic $1 に「${EPIC_HEADING#\#\# }」節が無い／未記入" >&2
    printf '## epic %s の前提\n\n（前提節なし・未記入）\n' "$1"; return
  fi
  printf '## epic %s の前提\n\n' "$1"
  printf '%s\n' "$sec" | sed 1d
}

find_epics() {  # <issue番号> → 祖先（自身を含む）の epic 番号を近い順に 1 行ずつ。
  # 最大 6 段（小タスク→issue→task→sub-epic→epic。sub-epic は 2 段まで: issue-hierarchy.md）
  local n="$1" _ labels
  for _ in 1 2 3 4 5 6; do
    labels=$(gh issue view "$n" --json labels -q '[.labels[].name]|join(",")') || return 1
    [[ ",$labels," == *",epic,"* ]] && echo "$n"
    n=$(gh issue view "$n" --json parent -q '.parent.number // empty') || return 1
    [ -z "$n" ] && return 0
  done
}

emit_epic() {  # <issue番号> : 祖先の epic をすべて探して前提を出す（sub-epic の前提を親 epic の前提より先に）
  local epics epic body
  epics=$(find_epics "${1#\#}") || { echo "ERROR: gh で issue を辿れない（認証・ネットワークを確認）" >&2; exit 1; }
  if [ -z "$epics" ]; then
    echo "WARN: #${1#\#} の祖先に epic が無い" >&2
    printf '\n## epic の前提\n\n（親 epic なし）\n'
    return
  fi
  while IFS= read -r epic; do
    body=$(gh issue view "$epic" --json body -q .body) || { echo "ERROR: epic #$epic の本文を取得できない" >&2; exit 1; }
    emit_epic_body "#$epic" "$body"
  done <<<"$epics"
}

case "${1:-}" in
  --no-epic) emit_project ;;
  --epic-body-file)
    [ -f "${2:-}" ] || { echo "ERROR: --epic-body-file にファイルを指定" >&2; exit 1; }
    emit_project; emit_epic_body "(file)" "$(cat "$2")" ;;
  --epic-only)
    case "${2:-}" in ''|-*) echo "ERROR: --epic-only に issue 番号を指定" >&2; exit 1 ;; esac
    emit_epic "$2" ;;
  ''|-*) echo "usage: $0 <issue番号> | --no-epic | --epic-only <issue番号> | --epic-body-file F" >&2; exit 1 ;;
  *) emit_project; emit_epic "$1" ;;
esac
