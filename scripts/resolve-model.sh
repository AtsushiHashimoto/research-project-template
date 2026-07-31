#!/usr/bin/env bash
# ============================================================
# role → モデル名の解決
# [Template] research-project-template 由来
# ============================================================
#
# .claude/model-policy.json を読み、role に対応するモデル名を返す。
# スキル側は具体的なモデル名を書かず、本スクリプト経由で解決すること。
#
# Usage:
#   MODEL=$(bash scripts/resolve-model.sh abstract-review)
#   Task(subagent_type=..., model="$MODEL", prompt=...)
#
#   bash scripts/resolve-model.sh --list       # 全 role の解決結果を表示
#   bash scripts/resolve-model.sh --disable fable   # 枠上限時に一時的に無効化
#   bash scripts/resolve-model.sh --enable fable
#
# 利用枠の上限に当たった場合:
#   disabled に追加すると、その モデル を primary に持つ role は fallback に降りる。
#   環境変数 MODEL_POLICY_DISABLE でも指定できる（カンマ区切り。設定ファイルより優先）。

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
POLICY="$REPO_ROOT/.claude/model-policy.json"

[ -f "$POLICY" ] || { echo "inherit"; exit 0; }   # ポリシーが無ければセッションのモデルを継承
command -v jq >/dev/null 2>&1 || { echo "inherit"; exit 0; }

disabled_list() {
  local from_file from_env
  from_file=$(jq -r '.disabled[]?' "$POLICY" 2>/dev/null | tr '\n' ',')
  from_env="${MODEL_POLICY_DISABLE:-}"
  echo "${from_file},${from_env}"
}

is_disabled() {
  local m="$1"
  echo ",$(disabled_list)," | grep -q ",${m},"
}

resolve() {
  local role="$1"

  # プロジェクト固有の上書きが最優先
  local ov
  ov=$(jq -r --arg r "$role" '.overrides[$r] // empty' "$POLICY" 2>/dev/null)
  if [ -n "$ov" ] && ! is_disabled "$ov"; then echo "$ov"; return; fi

  local primary
  primary=$(jq -r --arg r "$role" '.roles[$r].primary // empty' "$POLICY" 2>/dev/null)
  if [ -z "$primary" ]; then
    echo "inherit"   # 未定義の role はセッションのモデルを継承する
    return
  fi

  if ! is_disabled "$primary"; then echo "$primary"; return; fi

  # primary が無効なら fallback を順に降りる
  local fb
  while IFS= read -r fb; do
    [ -z "$fb" ] && continue
    if ! is_disabled "$fb"; then echo "$fb"; return; fi
  done < <(jq -r --arg r "$role" '.roles[$r].fallback[]?' "$POLICY" 2>/dev/null)

  echo "inherit"   # 全て無効なら継承にフォールバック
}

case "${1:-}" in
  --list)
    printf "%-18s %-10s %s\n" "ROLE" "RESOLVED" "PRIMARY(fallback)"
    while IFS= read -r r; do
      p=$(jq -r --arg r "$r" '.roles[$r].primary' "$POLICY")
      f=$(jq -r --arg r "$r" '[.roles[$r].fallback[]?]|join(",")' "$POLICY")
      printf "%-18s %-10s %s(%s)\n" "$r" "$(resolve "$r")" "$p" "$f"
    done < <(jq -r '.roles|keys[]' "$POLICY")
    d=$(disabled_list | tr -s ',' ' ' | xargs)
    [ -n "$d" ] && echo "disabled: $d"
    exit 0
    ;;
  --disable)
    [ -z "${2:-}" ] && { echo "usage: --disable <model>"; exit 1; }
    tmp=$(mktemp)
    jq --arg m "$2" '.disabled = ((.disabled // []) + [$m] | unique)' "$POLICY" > "$tmp" && mv "$tmp" "$POLICY"
    echo "disabled に追加: $2"
    ;;
  --enable)
    [ -z "${2:-}" ] && { echo "usage: --enable <model>"; exit 1; }
    tmp=$(mktemp)
    jq --arg m "$2" '.disabled = ((.disabled // []) - [$m])' "$POLICY" > "$tmp" && mv "$tmp" "$POLICY"
    echo "disabled から削除: $2"
    ;;
  "")
    echo "usage: resolve-model.sh <role> | --list | --disable <model> | --enable <model>"
    exit 1
    ;;
  *)
    resolve "$1"
    ;;
esac
