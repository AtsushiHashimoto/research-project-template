#!/usr/bin/env bash
# handoff.sh — セッションの区切りで、次のセッション（/clear・/compact 後や別の日）へ文脈を渡す
#              引き継ぎコメントの書き込みと読み出し（.claude/rules/template/deliverables.md「セッションの区切り」）
#
#   bash scripts/handoff.sh write <issue番号> <本文ファイル|->   # issue に引き継ぎコメントを投稿し、最後の引き継ぎ先として記録
#   bash scripts/handoff.sh read [<issue番号>]                  # その issue の最新の引き継ぎコメントを出力（省略時は最後の引き継ぎ先）
#   bash scripts/handoff.sh last                                # 最後の引き継ぎ先「<issue番号><TAB><URL>」を出力（無ければ空）
#
# 本文には下の REQUIRED の 4 つの見出しを必ず含める（見出しの単一情報源。ルール側はここを参照する）。
# 欠けていれば投稿しない（空の引き継ぎで「渡したつもり」になるのを防ぐ）。該当なしの見出しには「なし」と書く。
#
# 最後の引き継ぎ先は worktree ごとの git ディレクトリに記録する。main の旧記録だけ互換保持する。
# 中身は issue のコメントが正で、ここには番号と URL しか置かない。
#
# 終了コード: 0=成功（read で引き継ぎが無いときも 0。stderr に知らせる）/ 1=gh 失敗・本文の不備 / 2=引数不正
set -uo pipefail

# read が拾うのは、この印で始まり、リポジトリの関係者（OWNER / MEMBER / COLLABORATOR）が書いたコメントだけ
# （SessionStart フックで文脈に入るため、第三者のコメントや「## 引き継ぎ先について」等を拾わない）
MARKER='## 引き継ぎ（'
REQUIRED=('### 済んだこと' '### 決まったこと' '### 次の一手' '### 未解決の問い')

state_file() {
  local dir common
  dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  if [ "$dir" = "$common" ]; then
    echo "$dir/claude-handoff-last"  # main の既存記録を維持
  else
    echo "$dir/agent-handoff-last"   # 別 worktree の記録には fallback しない
  fi
}

usage() { sed -n '5,7p' "$0" | sed 's/^# //' >&2; exit 2; }

cmd_write() {
  local issue="${1:-}" src="${2:-}" body missing=() h url sf br
  issue="${issue#\#}"
  if ! [[ "$issue" =~ ^[0-9]+$ ]] || [ -z "$src" ]; then usage; fi
  if [ "$src" = "-" ]; then body=$(cat); else
    [ -f "$src" ] || { echo "ERROR: 本文ファイルが無い: $src" >&2; exit 1; }
    body=$(cat "$src")
  fi
  body=$(tr -d '\r' <<<"$body")
  for h in "${REQUIRED[@]}"; do
    grep -qxF -- "$h" <<<"$body" || missing+=("$h")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: 引き継ぎに見出しが足りない: ${missing[*]}（該当なしなら「なし」と書く）" >&2
    exit 1
  fi
  # 先頭の行が MARKER で始まるものだけを read が拾う。本文側に既にあれば重ねない
  if [[ "$(head -n1 <<<"$body")" != "$MARKER"* ]]; then
    br=$(git branch --show-current 2>/dev/null); [ -n "$br" ] || br='?'   # detached HEAD は空文字で成功する
    body="$MARKER$(date '+%Y-%m-%d %H:%M')・$br）"$'\n\n'"$body"
  fi
  url=$(gh issue comment "$issue" --body-file - <<<"$body") || { echo "ERROR: #$issue にコメントできない" >&2; exit 1; }
  url=$(tail -n1 <<<"$url")
  if sf=$(state_file); then
    printf '%s\t%s\n' "$issue" "$url" > "$sf"
  else
    echo "WARN: git リポジトリ外のため、最後の引き継ぎ先を記録していない" >&2
  fi
  echo "$url"
}

cmd_last() {
  local sf
  sf=$(state_file) || return 0
  [ -f "$sf" ] && head -n1 "$sf"
  return 0
}

cmd_read() {
  local issue="${1:-}" body
  if [ -z "$issue" ]; then
    issue=$(cmd_last | cut -f1)
    [ -n "$issue" ] || { echo "（引き継ぎの記録なし）" >&2; return 0; }
  fi
  issue="${issue#\#}"
  [[ "$issue" =~ ^[0-9]+$ ]] || usage
  body=$(gh issue view "$issue" --json comments \
           --jq "[.comments[] | select((.authorAssociation // \"\") | test(\"^(OWNER|MEMBER|COLLABORATOR)$\"))
                  | select(.body | startswith(\"$MARKER\"))] | last | .body // empty") \
    || { echo "ERROR: #$issue のコメントを取得できない" >&2; exit 1; }
  if [ -z "$body" ]; then
    echo "（#$issue に引き継ぎコメントなし）" >&2
    return 0
  fi
  printf '%s\n' "$body" | tr -d '\r'
}

case "${1:-}" in
  write) shift; cmd_write "$@" ;;
  read)  shift; cmd_read "$@" ;;
  last)  cmd_last ;;
  *)     usage ;;
esac
