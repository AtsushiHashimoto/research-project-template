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
  [ -n "$missing" ] || missing="- （検査の出力に FAILED の行が無い。上の出力を見ること）"
  body="## 停止: $what

- 時刻: $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M JST')
- 足りないもの（書く行つき）:
$missing
- 再実行: \`$rerun\`"
  # ★ 直前のコメントと同じ中身（時刻の行を除く）なら書かない。再実行のたびに同じ停止が積もるのを防ぐ
  last="$(gh_json "#$task のコメント取得" gh issue view "$task" --json body,comments,createdAt \
           | python3 -c 'import json,sys; c=json.load(sys.stdin)["comments"]; print(c[-1]["body"] if c else "")')"
  if [ "$(printf '%s' "$last" | grep -v '^- 時刻: ')" = "$(printf '%s' "$body" | grep -v '^- 時刻: ')" ]; then
    say "  --   #$task の直前のコメントが同じ停止なので、記録は書き足さない"
  else
    gh_json "#$task への停止の記録" gh issue comment "$task" --body "$body" >/dev/null
    say "  ..   止まった理由を #$task にコメントした"
  fi
  next_fail "止まった理由: $what" "" "足りないもの（書く行つき。<…> は中身に置き換える）:" "$missing" "" \
    "$@" "再実行: $rerun"
}

# goal の中身の判定は、ワーカーではなく verification のサブエージェントが書く（自己申告にしない）
goal_gate_launch() {  # goal_gate_launch <task番号>
  printf '%s\n' \
    "  goal の中身の判定が要るなら、verification のサブエージェントを起動する" \
    "  （モデルは bash scripts/resolve-model.sh verification）。渡す文:" \
    "    「task #$1 の本文の『## 目標の状態』と『## 未確定』を読み、次の 3 点を判定せよ。" \
    "      G1b: 成功条件が 1 文の合否の述語になっているか" \
    "      G3: 未確定に言及する語を削っても、何を作り何を測るかが残るか" \
    "      G4: 解釈が 1 つに定まるか" \
    "      前提（bash scripts/read-premises.sh $1 の出力を原文で貼る）に反していないかも見ること。" \
    "      結果を gh issue comment $1 で、見出し『## goal ゲート』の下に" \
    "      『- G1b: PASS — <根拠>』の形で 3 行書け（通らないなら PASS の代わりに FAIL と理由）」" \
    "  ★ FAIL なら「## 目標の状態」の直しをユーザーに頼み、直った本文をもう一度判定させる。本文を編集したら判定は無効になる（編集時刻より新しい判定だけ数える）"
}

# ★ `check merge` が落ちたときの案内（issue-finish.sh と commit.sh の 2 箇所から使う）
merge_check_hints() {  # merge_check_hints <N> <TASK>
  printf '%s\n' \
    "  1. ブランチ <type>/$2-* に居ること" \
    "  2. 'Refs #$1' を持つコミットがあること（'Closes #$1' は使わない。close は issue-finish.sh が行う）" \
    "  3. PR があり、本文に '## /review 結果' とその中身があること" \
    "     （/review を回し、各サブエージェントの判定を書く。要約で済ませない）" \
    "  4. PR 本文に '## 仕様整合' 節があること。照合は verification のサブエージェントに頼む" \
    "     （モデルは bash scripts/resolve-model.sh verification。仕様・task の goal と" \
    "      前提 bash scripts/read-premises.sh $2 の出力を原文で渡す）。節に書く行:" \
    "       - goal 書き換え: なし" \
    "       - （experiment・validation なら）positive control: <…> / matched-engineering: <…> / 格付け: <…>" \
    "     ❌ の項目と、格付け unverified-negative（triage していない negative）はマージしない"
}
