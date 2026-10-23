#!/usr/bin/env bash
#
# epic 1 つを、**1 回の呼び出しで 1 段だけ**進める状態機械。task-run.sh を呼ぶ。
#
#   bash scripts/flow/epic-cycle.sh <epic番号>
#
# 判定の実体は scripts/check-discipline.sh。ここには述語を書かない。

# shellcheck source=scripts/flow/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die "使い方: bash scripts/flow/epic-cycle.sh <epic番号>"
EPIC="$1"

labels="$(issue_labels "$EPIC")"
has_label "$labels" epic || die "#$EPIC は epic ラベルを持たない（labels=$labels）"

head2 "epic #$EPIC: $(issue_title "$EPIC")"

REPO="$(gh_repo)"
kids="$(sub_issues "$EPIC")"
[ -n "$kids" ] || die "#$EPIC に子が無い"

# ── 1. 葉の判定（sub-epic を持つなら降りる）─────────────────────
# ★ 判定の根拠は .claude/rules/template/issue-hierarchy.md の sub-epic
#   （「/epic-cycle の対象は sub-epic を持たない epic（葉）のみ」）
open_epics=""
for k in $kids; do
  kl="$(issue_labels "$k")"
  has_label "$kl" epic || continue
  [ "$(issue_state "$k")" = "OPEN" ] || continue
  open_epics="$open_epics $k"
done
if [ -n "${open_epics// /}" ]; then
  head2 "sub-epic がある（葉ではない）"
  for k in $open_epics; do printf '  #%s %s\n' "$k" "$(issue_title "$k")"; done
  die "どの sub-epic を回すかをユーザーに聞き、その番号でこのスクリプトを呼び直すこと
（.claude/rules/template/issue-hierarchy.md: /epic-cycle の対象は葉のみ）"
fi

# ── 2. open な task があれば task-run.sh を呼ぶ ──────────────────
open_tasks=""
for k in $kids; do
  kl="$(issue_labels "$k")"
  has_label "$kl" task || continue
  [ "$(issue_state "$k")" = "OPEN" ] || continue
  open_tasks="$open_tasks $k"
done

if [ -n "${open_tasks// /}" ]; then
  # ★ `| head` を使わない（pipefail 下で生産者が SIGPIPE で死ぬ）。
  #   bash の配列で最小値を取る
  local_min=""
  for x in $open_tasks; do
    [ -z "$local_min" ] || [ "$x" -lt "$local_min" ] && local_min="$x"
  done
  t="$local_min"
  head2 "open な task #$t を進める"
  # ★ **呼ぶ**（exec しない）。戻り値を見る（終了コードは task-run のまま返す）
  rc=0; bash "$REPO_ROOT/scripts/flow/task-run.sh" "$t" || rc=$?
  # ★ 子が全て closed（task-run が区切りで 0 を返した）なら、epic-cycle へ戻る案内を足す
  if [ "$rc" = 0 ]; then
    still_open=0
    for k in $(sub_issues "$t"); do
      if [ "$(issue_state "$k")" = "OPEN" ]; then still_open=1; fi
    done
    [ "$still_open" = 1 ] || epic_return_step "$EPIC"
  fi
  exit "$rc"
fi

# ── 3. 乖離検査（GitHub 上の成果物で見る）──────────────────────
# ※ この判定は将来 check-discipline.sh へ移す。
#   いまは epic-cycle に直書きしており、語境界の照合が 2 箇所にある。
# ★ 「このサイクルの開始時刻」＝ epic 配下で直近に closed になった task の closedAt。
#   無ければ epic 自身の createdAt。**data/local/ に書かない**（自己申告になる）
# ★ gh の失敗は gh_json で die する（`x="$(gh … 2>/dev/null)"` は set -e 下で代入の時点で
#   無言終了し、下のフォールバックにも届かない。lib.sh の gh_json の注記）
since="$(gh_json "epic #$EPIC の sub_issues の closed_at 取得" gh api "repos/$REPO/issues/$EPIC/sub_issues" \
          --jq '[.[]|select(.state=="closed")|.closed_at]|max // empty')"
[ -n "$since" ] || since="$(gh_json "epic の createdAt" gh issue view "$EPIC" --json createdAt -q .createdAt)"

head2 "乖離検査（サイクル開始 $since 以降）"
ri="$(gh issue list --label review-integrity --state all --limit 50 \
       --json number,createdAt,body \
       --jq "[.[]|select(.createdAt > \"$since\")|select(.body|test(\"(^|[^0-9])#${EPIC}([^0-9]|\$)\"))]|length" \
       2>/dev/null)" || die "gh issue list が失敗した"

if [ "${ri:-0}" -lt 1 ]; then
  next_fail \
    "このサイクルで乖離検査を走らせていない。" \
    "" \
    "  1. /issue-gaps  — 仕様と実装の乖離を検出し、新規 issue は epic #$EPIC 配下に作る" \
    "  2. /review-integrity — バグ・デッドコード・配線不備を検出し、" \
    "     review-integrity ラベルの報告 issue を起票する" \
    "     ★ **その本文に #$EPIC を含めること**（他 epic 向けの報告では通らない）"
fi
say "  ok   review-integrity の報告 $ri 件（$since 以降、#$EPIC を参照）"

# ── 4. 次 task の判断（スクリプトでは判定しない）────────────────
head2 "紐づかないコミットの計数"
# ★ **失敗を握り潰さない**。握り潰すと、出ていない数字を報告に使うことになる
check epic "$EPIC" || die "epic の計数が失敗した"

# ★ 達成判定コメントがあるなら、完了条件との照合をここで掛ける
head2 "達成判定の照合"
vrc=0; vout="$(check verdict "$EPIC" 2>&1)" || vrc=$?
printf '%s\n' "$vout"
if [ "$vrc" = 0 ]; then
  say "  ok   達成判定コメントが完了条件を 1 項目ずつ引用している"
else
  gate_stop "$EPIC" "epic #$EPIC の達成判定コメント（完了条件の引用・全部 negative のときの確認）が揃っていない" \
    "$vout" "bash scripts/flow/epic-cycle.sh $EPIC" \
    "  gh issue comment $EPIC で『## 判定』の見出しのコメントを書く:" \
    "    ★ **完了条件を 1 項目ずつ引用**（チェックボックスを除いた本文をそのまま）" \
    "    ★ 閉じた task の結果がすべて negative なら『## 全部 negative の確認』節を足し、" \
    "      効くはずの状況で検出できること（positive control）を確かめ直した記述を書く" \
    "      （全部 negative は、まず検出力の不足か実装の誤りを疑う）" \
    "★ 次の task が必要なら、判定の前に /task-start で作ること" \
    "  （結果駆動。投機禁止。2 周目以降も survey を skip しない）。" ""
fi

next_final \
  "epic #$EPIC の全 task が closed で、乖離検査も済んでいる。次は**判断**である。" \
  "" \
  "  A. 次の task が必要か（結果駆動。**投機禁止**。結果が出てから作る）" \
  "     - goal を読み直し、「この goal に照らして必要か」で判断する" \
  "     - 必要なら /task-start で作る（2 周目以降も survey を skip しない）" \
  "" \
  "  B. 不要なら epic の達成判定を行い、gh issue comment で記録する" \
  "     ★ コメントに '## 判定' の見出しを含めること" \
  "     ★ **完了条件を 1 項目ずつ引用**すること（引用が無い項目があると次回落ちる）" \
  "" \
  "★ goal は書き換えない。goal を小さく読まない。" \
  "  変更が必要なら**新しい epic を立て**、この epic は「達成されなかった」記録として閉じる。" \
  "" \
  "$(handoff_steps "$EPIC" epic-cycle)"
