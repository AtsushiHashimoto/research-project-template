#!/usr/bin/env bash
#
# 判断ゲートで止まったときの出力と記録（lib.sh から読み込まれる。単体では実行しない）。
# ★ 述語はここに書かない（単一情報源は scripts/check-discipline.sh とその部品）。
#   ここに置くのは「止まった理由を task に 1 回だけ書く」ことと、止まったときに読ませる文だけ。

# ★ 停止の 3 点（足りないもの・書く行・再実行コマンド）を 1 回で全部出す。
#   落ちた行を 1 行ずつ止めると、直すたびに次の 1 行が出てきて往復が増える。
# gate_stop <task番号> <ゲートの中身（平文）> <検査の出力> <再実行コマンド> [<追加の行>...]
gate_stop() {
  local task="$1" what="$2" out="$3" rerun="$4"; shift 4
  local missing body last
  # 検査の出力のうち FAILED の行と、その下の「書く行:」「直し方:」の行だけを拾う
  missing="$(printf '%s\n' "$out" | awk '/^!!! FAILED: /{sub(/^!!! FAILED: /,"- "); print; keep=1; next}
      keep && /^     /{print "  " substr($0,6); next} {keep=0}')"
  # FAILED の行が無ければ出力を丸ごと載せる（呼び出し側は落ちたとき出力を出さない）
  [ -n "$missing" ] || missing="- 検査の出力に FAILED の行が無い。出力:
$(printf '%s\n' "$out" | sed 's/^/    /')"
  body="## 停止: $what

- 時刻: $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M JST')
- 足りないもの（書く行つき）:
$missing
- 再実行: \`$rerun\`"
  # ★ 先に 3 点を出す（記録の投稿が落ちても、止まった理由は失わない）。サブシェルで出して戻る
  ( next_fail "止まった理由: $what" "" "足りないもの（書く行つき。<…> は中身に置き換える）:" "$missing" "" \
    "$@" "再実行: $rerun" ) || true
  # ★ 直前のコメントと同じ中身（時刻の行を除く）なら書かない。再実行のたびに同じ停止が積もるのを防ぐ
  if ! last="$(gh issue view "$task" --json body,comments,createdAt 2>/dev/null \
           | python3 -c 'import json,sys; c=json.load(sys.stdin)["comments"]; print(c[-1]["body"] if c else "")')"; then
    say "!!! 警告: #$task のコメントを読めず、停止の記録を書いていない（止まった理由は上のとおり）"
  elif [ "$(printf '%s' "$last" | grep -v '^- 時刻: ')" = "$(printf '%s' "$body" | grep -v '^- 時刻: ')" ]; then
    say "  --   #$task の直前のコメントが同じ停止なので、記録は書き足さない"
  elif gh issue comment "$task" --body "$body" >/dev/null 2>&1; then
    say "  ..   止まった理由を #$task にコメントした"
  else
    say "!!! 警告: #$task への停止の記録を書けなかった（止まった理由は上のとおり）"
  fi
  exit 1
}

# goal の中身の判定は、ワーカーではなく verification のサブエージェントが書く（自己申告にしない）
# ★ 判定の項目は check-discipline-gates.py の GOAL_KEYS が単一情報源（ここに書き写さない）
goal_gate_launch() {  # goal_gate_launch <task番号>
  local keys
  keys="$(python3 -B "$REPO_ROOT/scripts/check-discipline-gates.py" goal-keys | sed 's/^/      /')" \
    || keys="      （判定の項目を scripts/check-discipline-gates.py goal-keys から読めなかった）"
  printf '%s\n' \
    "goal の中身の判定が要るなら、verification のサブエージェントを起動する" \
    "  （モデルは bash scripts/resolve-model.sh verification）。渡す文:" \
    "    「task #$1 の本文の『## 目標の状態』と『## 未確定』を読み、次の各項目を判定せよ。" \
    "$keys" \
    "      前提（bash scripts/read-premises.sh $1 の出力を原文で貼る）に反していないかも見ること。" \
    "      結果を gh issue comment $1 で、見出し『## goal ゲート』の下に、上の書く行の" \
    "      『目標の状態の hash: …』と、項目ごとに『- <項目>: PASS — <根拠>』の行を書け（通らないなら FAIL と理由）」" \
    "  ★ FAIL なら「## 目標の状態」の直しをユーザーに頼み、直った本文をもう一度判定させる。" \
    "    判定は「## 目標の状態」の hash で本文と結びつく（直したら hash が変わり、判定し直しになる。" \
    "    「## 未確定」の書き換えでは変わらない）。判定コメントは編集せず、新しく書く"
}

# ★ `check merge`・`check reentry` が落ちたときの案内（issue-finish.sh と commit.sh から使う）。
#   **落ちた項目の分だけ**出す。書く行は検査の FAILED の側が持つので、ここはサブエージェントの起動だけ
merge_check_hints() {  # merge_check_hints <N> <TASK> <検査の出力>
  local line rev=0 conf=0
  while IFS= read -r line; do
    case "$line" in
      '!!! FAILED: PR: '*|'!!! FAILED: '*'/review 結果'*) rev=1;;
      '!!! FAILED: '*仕様整合*|'!!! FAILED: '*格付け*|'!!! FAILED: conformance '*) conf=1;;
    esac
  done <<< "${3:-}"
  [ "$rev" = 0 ] || printf '%s\n' \
    "  /review を回し、PR 本文の「## /review 結果」の下にサブエージェントごとに 1 行ずつ判定を書く（要約で済ませない）"
  [ "$conf" = 0 ] || printf '%s\n' \
    "  仕様整合の照合は verification のサブエージェントに頼む（モデルは bash scripts/resolve-model.sh verification。" \
    "  仕様・task の goal と前提 bash scripts/read-premises.sh $2 の出力を原文で渡す）。" \
    "  ❌ の項目と、格付け unverified-negative（triage していない negative）はマージしない"
  return 0
}
