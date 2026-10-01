#!/usr/bin/env bash
# handoff.sh / session-context.sh / ensure-claude-hooks.sh の回帰テスト
# （ネットワーク不要。gh はスタブ、git は一時リポジトリ）
# shellcheck disable=SC2015  # ok/ng は常に 0 を返すので A&&B||C で安全
set -uo pipefail
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()   { [ "$QUIET" = 1 ] || echo "ok   $1"; }
ng()   { echo "FAIL $1"; FAIL=1; }
has()  { grep -qF -- "$2" <<<"$1" && ok "$3" || ng "$3"; }
hasnt(){ grep -qF -- "$2" <<<"$1" && ng "$3" || ok "$3"; }

command -v jq >/dev/null 2>&1 || { echo "skip: jq が無い"; exit 0; }

# --- gh スタブ: $FIX/<番号>.json を issue とみなす。comment は $FIX/<番号>.posted に追記 ---
FIX="$TMP/fix"; mkdir -p "$FIX" "$TMP/bin"
cat > "$TMP/bin/gh" <<'X'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
[ "$1 $2" = "issue comment" ] && { cat >> "$FIX/$3.posted"; echo "https://example.invalid/issues/$3#issuecomment-1"; exit 0; }
[ "$1 $2" = "issue view" ] || exit 1
n=$3; q='.'
while [ $# -gt 0 ]; do case "$1" in --jq|-q) q=$2; shift ;; esac; shift; done
[ -f "$FIX/$n.json" ] || exit 1
jq -r "$q" "$FIX/$n.json"
X
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FIX

# --- 一時リポジトリ（テンプレートのスクリプトを置く） ---
R="$TMP/repo"; mkdir -p "$R/scripts" "$R/.spec"
cp "$ROOT/scripts/handoff.sh" "$ROOT/scripts/session-context.sh" "$ROOT/scripts/read-premises.sh" \
   "$ROOT/scripts/ensure-claude-hooks.sh" "$R/scripts/"
git -C "$R" init -q -b main && git -C "$R" add scripts \
  && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m init
cd "$R" || exit 1

GOOD=$'### 済んだこと\n- A を実装\n### 決まったこと\n- B にする\n### 次の一手\n- C を測る\n### 未解決の問い\nなし'

# 1: 見出しが欠けた引き継ぎは投稿しない
out=$(printf '### 済んだこと\n- x\n' | bash scripts/handoff.sh write 7 - 2>&1); rc=$?
[ $rc = 1 ] && ok "見出し不足は exit 1" || ng "見出し不足は exit 1 (rc=$rc)"
has "$out" "### 次の一手" "足りない見出しを示す"
[ -f "$FIX/7.posted" ] && ng "見出し不足では投稿しない" || ok "見出し不足では投稿しない"

# 2: 正しい引き継ぎは投稿され、先頭に印が付き、最後の引き継ぎ先が記録される
url=$(bash scripts/handoff.sh write 7 - <<<"$GOOD" 2>/dev/null); rc=$?
[ $rc = 0 ] && ok "投稿は exit 0" || ng "投稿は exit 0 (rc=$rc)"
has "$url" "issuecomment" "コメント URL を返す"
[[ "$(head -n1 "$FIX/7.posted")" == "## 引き継ぎ"* ]] && ok "先頭に印" || ng "先頭に印"
last=$(bash scripts/handoff.sh last)
[ "$(cut -f1 <<<"$last")" = 7 ] && ok "最後の引き継ぎ先を記録" || ng "最後の引き継ぎ先を記録 ($last)"
has "$(cat "$(git rev-parse --path-format=absolute --git-common-dir)/claude-handoff-last")" "7" "記録は git 共通ディレクトリ"
[ -z "$(git status --porcelain)" ] && ok "作業ツリーを汚さない" || ng "作業ツリーを汚さない"

# 3: read は印の付いた最新のコメントだけを返す
jq -n '{title:"T7", state:"OPEN", labels:[], parent:null, comments:[
  {body:"## 引き継ぎ（古い）\n### 次の一手\n- OLD"},
  {body:"ふつうのコメント"},
  {body:"## 引き継ぎ（新しい）\r\n### 次の一手\r\n- NEW"},
  {body:"後の雑談"}]}' > "$FIX/7.json"
out=$(bash scripts/handoff.sh read 7)
has "$out" "NEW" "最新の引き継ぎを返す"; hasnt "$out" "OLD" "古い引き継ぎを返さない"
hasnt "$out" "雑談" "印の無いコメントを返さない"
grep -q $'\r' <<<"$out" && ng "CR を除去" || ok "CR を除去"
out=$(bash scripts/handoff.sh read)
has "$out" "NEW" "番号省略時は最後の引き継ぎ先を読む"

# 4: 引き継ぎが無い issue は空出力で exit 0
jq -n '{title:"T8", state:"OPEN", labels:[], parent:null, comments:[]}' > "$FIX/8.json"
out=$(bash scripts/handoff.sh read 8 2>"$TMP/err"); rc=$?
[ $rc = 0 ] && [ -z "$out" ] && ok "引き継ぎなしは空で exit 0" || ng "引き継ぎなしは空で exit 0"
has "$(cat "$TMP/err")" "引き継ぎコメントなし" "引き継ぎなしを知らせる"

# 5: session-context — main では最後の引き継ぎ先を使う
out=$(bash scripts/session-context.sh </dev/null)
has "$out" "#7 T7" "main では最後の引き継ぎ先"; has "$out" "NEW" "引き継ぎを出す"
has "$out" "親 epic なし" "epic 前提を出す"

# 6: ブランチ名の番号が最優先。worktree 一覧も出す
git branch -q feature/8-x && git worktree add -q "$TMP/wt8" feature/8-x 2>/dev/null
out=$(cd "$TMP/wt8" && bash "$R/scripts/session-context.sh" </dev/null)
has "$out" "#8 T8" "ブランチの番号を使う"; has "$out" "ブランチ feature/8-x" "決め方を示す"
has "$out" "(feature/8-x)" "worktree 一覧"

# 7: gh が失敗しても exit 0 でセッションを止めない
out=$(GH_FAIL=1 bash scripts/session-context.sh </dev/null); rc=$?
[ $rc = 0 ] && ok "gh 失敗でも exit 0" || ng "gh 失敗でも exit 0 (rc=$rc)"
has "$out" "取得できない" "gh 失敗を注記"

# 8: フック入力（JSON）が stdin に来ても動く
out=$(echo '{"source":"clear"}' | bash scripts/session-context.sh 8); rc=$?
[ $rc = 0 ] && ok "stdin の JSON を読み捨てる" || ng "stdin の JSON を読み捨てる"
has "$out" "#8 T8" "引数の番号を使う"

# 9: ensure-claude-hooks — 既存設定を保って追記し、2回目は何もしない
mkdir -p .claude
echo '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo other"}]}]}}' > .claude/settings.json
bash scripts/ensure-claude-hooks.sh --check >/dev/null 2>&1; [ $? = 1 ] && ok "--check で未登録は exit 1" || ng "--check で未登録は exit 1"
bash scripts/ensure-claude-hooks.sh >/dev/null || ng "追記 exit 0"
bash scripts/ensure-claude-hooks.sh >/dev/null || ng "2回目 exit 0"
n=$(jq '[.hooks.SessionStart[].hooks[].command | select(contains("session-context.sh"))] | length' .claude/settings.json)
[ "$n" = 1 ] && ok "冪等（1件だけ登録）" || ng "冪等（1件だけ登録）: $n"
[ "$(jq -r '.permissions.allow[0]' .claude/settings.json)" = "Bash(ls)" ] && ok "既存の権限を保つ" || ng "既存の権限を保つ"
[ "$(jq '[.hooks.SessionStart[].hooks[].command | select(. == "echo other")] | length' .claude/settings.json)" = 1 ] \
  && ok "既存のフックを保つ" || ng "既存のフックを保つ"
bash scripts/ensure-claude-hooks.sh --check >/dev/null && ok "--check で登録済みは exit 0" || ng "--check で登録済みは exit 0"
echo '{broken' > .claude/settings.json
bash scripts/ensure-claude-hooks.sh >/dev/null 2>&1; [ $? = 1 ] && ok "壊れた JSON は exit 1" || ng "壊れた JSON は exit 1"
[ "$(cat .claude/settings.json)" = '{broken' ] && ok "壊れた JSON を上書きしない" || ng "壊れた JSON を上書きしない"
rm .claude/settings.json; bash scripts/ensure-claude-hooks.sh >/dev/null && [ -f .claude/settings.json ] \
  && ok "settings.json が無ければ作る" || ng "settings.json が無ければ作る"

[ $FAIL = 0 ] && { [ "$QUIET" = 1 ] || echo "all passed"; exit 0; } || exit 1
