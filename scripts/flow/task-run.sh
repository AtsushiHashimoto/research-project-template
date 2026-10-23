#!/usr/bin/env bash
#
# task 1 つ分の仕事を、**1 回の呼び出しで 1 段だけ**進める状態機械。
#
#   bash scripts/flow/task-run.sh <task番号>
#
# 散文の「絶対にスキップしない」は効かなかったので、意図の表明（散文）と強制（プログラム）を分ける。
#
# 状態はファイルに持たない。GitHub の open/closed と git から導く。
# 判定の実体は scripts/check-discipline.sh。ここには述語を書かない。

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die "使い方: bash scripts/flow/task-run.sh <task番号>"
TASK="$1"

# ── 0. task の妥当性 ────────────────────────────────────────────
labels="$(issue_labels "$TASK")"
has_label "$labels" task || die "#$TASK は task ラベルを持たない（labels=$labels）"

head2 "task #$TASK: $(issue_title "$TASK")"

# ★ closed 済みの task には完了判定を案内しない（閉じた後に呼ぶと済んだ判定を再び促していた）
if [ "$(issue_state "$TASK")" = "CLOSED" ]; then
  next "task #$TASK は closed 済み（完了判定は済んでいる）。" \
    "次の task は /epic-cycle で選ぶ（ここでは作らない）。"
fi

# ── 1. 子 issue を既定順に並べる ─────────────────────────────────
kids="$(sub_issues "$TASK")"
[ -n "$kids" ] || die "#$TASK に子 issue が無い。/task-start で作ること"

declare -a ordered=()
declare -A kind_of_kid=() skip_of_kid=()
for k in $kids; do
  kl="$(issue_labels "$k")"
  kk="$(kind_of "$kl")"
  # ★ 種類ラベルを持たない子・未知のラベルの子は**黙って飛ばさない**
  [ -n "$kk" ] || die "#$k が種類ラベルを持たない（labels=$kl）。ラベルを付けること"
  kind_of_kid["$k"]="$kk"
  # ★ 状態ラベルの子は飛ばす（labels.md「自動処理でスキップ」）。飛ばしたことは段 2 で必ず出す
  for sl in user-action blocked out-of-date; do
    if has_label "$kl" "$sl"; then skip_of_kid["$k"]="$sl"; break; fi
  done
done
for want in $DEFAULT_ORDER $EXTRA_ORDER; do
  for k in $(printf '%s\n' "$kids" | sort -n); do
    [ "${kind_of_kid[$k]}" = "$want" ] && ordered+=("$k")
  done
done

# ── 2. いまの段を決める（open な最初のもの）────────────────────
current=""
declare -a done_kids=() skipped=()
for k in "${ordered[@]}"; do
  st="$(issue_state "$k")"
  if [ "$st" = "OPEN" ] && [ -n "${skip_of_kid[$k]:-}" ]; then
    # ★ 飛ばすのは既定構成の後ろに並ぶ種類（EXTRA_ORDER）だけ。既定構成の段を飛ばすと
    #   validation が済まないまま experiment へ進める（issue-hierarchy.md）ので、そこでは止める
    case " $EXTRA_ORDER " in
      *" ${kind_of_kid[$k]} "*) ;;
      *) next_fail "#$k [${kind_of_kid[$k]}] に ${skip_of_kid[$k]} ラベルが付いている。**既定構成の段は飛ばさない。**" "" \
           "  - ユーザー対応・ブロックの解消を待ち、ラベルを外してから再び呼ぶ" ;;
    esac
    say "  --   #$k [${kind_of_kid[$k]}] は ${skip_of_kid[$k]} ラベル付きなので飛ばす（ラベルを外すと再び対象になる）"
    skipped+=("#$k(${skip_of_kid[$k]})"); continue
  fi
  if [ "$st" = "OPEN" ]; then current="$k"; break; fi
  done_kids+=("$k")
done

# ── 3. closed の先行段を検査（成果物だけ）──────────────────────
if [ "${#done_kids[@]}" -gt 0 ]; then
  head2 "closed の先行段を検査（成果物だけ）"
  bad=0
  for k in "${done_kids[@]}"; do
    # ★ `gh issue close` を直に呼べば成果物なしで段が進む。これを塞ぐ
    check artifacts "$k" "${kind_of_kid[$k]}" || bad=1
  done
  # ★ base ref が古いと、正しく閉じた段でもコミットが見つからず落ちる。
  #   原因の取り違えを防ぐため、その可能性を診断に書く
  [ "$bad" = 0 ] || die "先行段の成果物が揃っていない。
  成果物なしで閉じた段があるか、**origin/main が古い**。
  後者なら \`git fetch origin\` を実行してから再度呼ぶこと"
fi

# ── 4. 全て closed なら task の完了判定へ ───────────────────────
# ★ 飛ばした子が open で残っているなら「全て closed」ではない。完了判定へ進ませない
if [ -z "$current" ] && [ "${#skipped[@]}" -gt 0 ]; then
  next_fail \
    "task #$TASK: 残っている open な子は状態ラベル付きで飛ばしたものだけ（${skipped[*]}）。" \
    "" \
    "  - ユーザー対応・ブロックの解消を待つ。済んだらラベルを外して再び呼ぶ" \
    "    （close するなら bash scripts/flow/issue-finish.sh で。直に閉じると段 3 の成果物の検査で落ちる）" \
    "  - ★ ラベルを外さずに task を閉じない（完了判定は全ての子が closed になってから）"
fi
if [ -z "$current" ]; then
  head2 "全ての子 issue が closed"
  next_final \
    "task #$TASK の完了判定を行う。" \
    "" \
    "  1. 本文の「目標の状態」の**成功条件を 1 項目ずつ照合する**" \
    "     （未充足が 1 つでもあれば「達成」としない）" \
    "  2. 「negative の意味」も照合対象に含める" \
    "  3. 「未確定」節に残る項目を 1 つずつ照合する" \
    "  4. 結果を gh issue comment で #$TASK に記録し、達成なら close する" \
    "" \
    "★ goal を書き換えて「達成」にしない。goal を小さく読んで「達成」にしない。" \
    "★ 次の task は**ここでは作らない**（結果駆動の task 生成は epic-cycle が統括する）。" \
    "" \
    "$(handoff_steps "$TASK")"
fi

kind="${kind_of_kid[$current]}"
head2 "いまの段: #$current [$kind] $(issue_title "$current")"

# ── 5. その段の前提を検査 ───────────────────────────────────────
# ★ ブランチは **task 単位**なので $TASK で見る
if check issue "$current" "$kind" "$TASK"; then
  head2 "前提は揃っている。品質チェックへ"
  run_quality "$kind"
  next \
    "#$current の成果物は揃い、品質チェックも通った。" \
    "" \
    "  1. /issue-report で進捗を #$current に記録する" \
    "  2. spec 段なら .spec/issues/$current-*.md の「ステータス:」を completed にする" \
    "  3. /review を回し、結果を PR 本文の「## /review 結果」に書く" \
    "  4. git add <ファイル名> で入れるものを**名前で** stage し、" \
    "     bash scripts/flow/commit.sh push --issue $current --message <題>" \
    "     gh pr create で PR を作る（本文に 'Refs #$current'。Closes は書かない。close は issue-finish.sh が行う）" \
    "  5. bash scripts/flow/issue-finish.sh $current $TASK" \
    "     （検査 → マージ → close をこれが行う。PR 本文はモデルが書く）"
fi

# ── 6. 揃っていない → 何を作ればよいかを出す ────────────────────
case "$kind" in
  survey)
    next_fail \
      "#$current は survey の段である。" \
      "" \
      "  1. bash scripts/flow/issue-start.sh $current を呼び、出力された cd 先へ移る" \
      "  2. docs/surveys/<日付>_<題>.md を書く。**本文に #$current を含めること**" \
      "     （語境界つき。その issue のために書かれたことが辿れるようにする）" \
      "  3. 追加調査が不要という判断でも、**skip ではなく判断の記録を残す**" ;;
  spec)
    next_fail \
      "#$current は spec の段である。" \
      "" \
      "  1. bash scripts/flow/issue-start.sh $current を呼び、出力された cd 先へ移る" \
      "     （★ spec 段でも check_branch が掛かる。main に居ては前提が揃わない）" \
      "  2. .spec/issues/$current-<題>.md を書く" \
      "     **1 行目の見出しに #$current を含めること**" \
      "  3. auto-reviewer に代理判断させ、" \
      "     .spec/issues/$current-auto-decisions.md を書き出させる" \
      "     **本文に 'Issue #$current' と '停止条件' を含めること**" \
      "     モデルは bash scripts/resolve-model.sh abstract-review で解決する" \
      "  4. 停止条件に該当したら**進まずに報告する**" ;;
  *)
    next_fail \
      "#$current は $kind の段である。" \
      "" \
      "  1. bash scripts/flow/issue-start.sh $current を呼び、出力された cd 先へ移る" \
      "  2. 実装・測定を行い、作業差分を作る" \
      "     （★ この段は**仕様ファイルを要求しない**。仕様は spec 段の番号で" \
      "       作られるので、$kind の番号では引きようがない）" \
      "  3. experiment の段なら data/shared/experiments/<日付>_<名>/ に" \
      "     README.md（**本文に #$current**）・data/・figures/ の 3 点セットを作る" ;;
esac
