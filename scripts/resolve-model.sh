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
#
# disabled の書き込み先:
#   --disable / --enable は .claude/model-policy.local.json（gitignore 対象）に書く。
#   枠上限は個人・一時的な事情であり、共有される .claude/model-policy.json を
#   書き換えると git が汚れて偽の還流候補になるため。
#   読み取りは local + 本体（後方互換）+ 環境変数の和を取る。

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
POLICY="$REPO_ROOT/.claude/model-policy.json"
LOCAL_POLICY="$REPO_ROOT/.claude/model-policy.local.json"

[ -f "$POLICY" ] || { echo "inherit"; exit 0; }   # ポリシーが無ければセッションのモデルを継承
command -v jq >/dev/null 2>&1 || { echo "inherit"; exit 0; }

# 指定ファイルの .disabled をカンマ区切りで返す（ファイルが無ければ空）
disabled_in_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  jq -r '.disabled[]?' "$f" 2>/dev/null | tr '\n' ','
}

disabled_list() {
  local from_local from_file from_env
  from_local=$(disabled_in_file "$LOCAL_POLICY")
  from_file=$(disabled_in_file "$POLICY")     # 後方互換: 旧バージョンが書いた本体側も読む
  from_env="${MODEL_POLICY_DISABLE:-}"
  echo "${from_local},${from_file},${from_env}"
}

is_disabled() {
  local m="$1"
  echo ",$(disabled_list)," | grep -q ",${m},"
}

# role に適用される override を返す（$comment などのメタキーは除外）
override_for() {
  local role="$1"
  [ "${role#\$}" = "$role" ] || return 0   # $ 始まりはメタキー
  jq -r --arg r "$role" '.overrides[$r] // empty' "$POLICY" 2>/dev/null
}

resolve() {
  local role="$1"

  # プロジェクト固有の上書きが最優先
  local ov
  ov=$(override_for "$role")
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

# $1 のファイルの .disabled から $2 を削除する。削除したら 0、対象が無ければ 1
remove_disabled_from() {
  local f="$1" m="$2" tmp
  [ -f "$f" ] || return 1
  jq -e --arg m "$m" '(.disabled // []) | index($m) != null' "$f" >/dev/null 2>&1 || return 1
  tmp=$(mktemp)
  if jq --arg m "$m" '.disabled = ((.disabled // []) - [$m])' "$f" > "$tmp" && mv "$tmp" "$f"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

case "${1:-}" in
  --list)
    printf "%-18s %-10s %-22s %s\n" "ROLE" "RESOLVED" "PRIMARY(fallback)" "OVERRIDE"
    while IFS= read -r r; do
      p=$(jq -r --arg r "$r" '.roles[$r].primary' "$POLICY")
      f=$(jq -r --arg r "$r" '[.roles[$r].fallback[]?]|join(",")' "$POLICY")
      ov=$(override_for "$r")
      if [ -z "$ov" ]; then
        ov_note="-"
      elif is_disabled "$ov"; then
        ov_note="$ov (disabled のため未適用)"
      else
        ov_note="$ov (適用中)"
      fi
      printf "%-18s %-10s %-22s %s\n" "$r" "$(resolve "$r")" "$p($f)" "$ov_note"
    done < <(jq -r '.roles|keys[]' "$POLICY")

    ov_all=$(jq -r '[.overrides // {} | to_entries[] | select(.key|startswith("$")|not) | "\(.key)=\(.value)"] | join(" ")' "$POLICY" 2>/dev/null)
    if [ -n "$ov_all" ]; then
      echo "overrides: $ov_all  (.claude/model-policy.json)"
    else
      echo "overrides: なし"
    fi

    d=$(disabled_list | tr -s ',' ' ' | xargs)
    [ -n "$d" ] && echo "disabled: $d"
    exit 0
    ;;
  --disable)
    [ -z "${2:-}" ] && { echo "usage: --disable <model>"; exit 1; }
    [ -f "$LOCAL_POLICY" ] || echo '{}' > "$LOCAL_POLICY"
    tmp=$(mktemp)
    if ! { jq --arg m "$2" '.disabled = ((.disabled // []) + [$m] | unique)' "$LOCAL_POLICY" > "$tmp" && mv "$tmp" "$LOCAL_POLICY"; }; then
      rm -f "$tmp"; exit 1
    fi
    echo "disabled に追加: $2 (.claude/model-policy.local.json)"
    ;;
  --enable)
    [ -z "${2:-}" ] && { echo "usage: --enable <model>"; exit 1; }
    removed=0
    if remove_disabled_from "$LOCAL_POLICY" "$2"; then
      echo "disabled から削除: $2 (.claude/model-policy.local.json)"
      removed=1
    fi
    # 旧バージョンが本体 json に書いた legacy エントリも解除する（黙って残さない）
    if remove_disabled_from "$POLICY" "$2"; then
      echo "disabled から削除: $2 (.claude/model-policy.json ※旧形式。git の差分に出ます)"
      removed=1
    fi
    [ "$removed" -eq 0 ] && echo "disabled に $2 はありませんでした"
    # 解除しきれない残存（環境変数など）は明示する
    if is_disabled "$2"; then
      src=""
      grep -q ",$2," <<<",$(disabled_in_file "$LOCAL_POLICY")," && src="$src .claude/model-policy.local.json"
      grep -q ",$2," <<<",$(disabled_in_file "$POLICY")," && src="$src .claude/model-policy.json"
      grep -q ",$2," <<<",${MODEL_POLICY_DISABLE:-}," && src="$src 環境変数 MODEL_POLICY_DISABLE"
      echo "⚠️  $2 は依然として disabled です（残存:${src:- 不明}）。解決結果は fallback のままです"
      exit 1
    fi
    ;;
  "")
    echo "usage: resolve-model.sh <role> | --list | --disable <model> | --enable <model>"
    exit 1
    ;;
  *)
    resolve "$1"
    ;;
esac
