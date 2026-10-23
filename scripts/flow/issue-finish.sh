#!/usr/bin/env bash
#
# issue を完了する。検査 → マージの呼び出し → close。
#
#   bash scripts/flow/issue-finish.sh <issue番号> [<task番号>]
#
# ★ **close を行うのはこのスクリプトだけ**（commit.sh merge はマージと後片付けだけ）。
# ★ **PR は作らない**。PR 本文の `## /review 結果` はモデルが書くので、
#   スクリプトが空の PR を作れると「作った側が検査する」＝恒真に近づく。
# ★ マージの実体は $MERGE_CMD = scripts/flow/commit.sh merge。

# shellcheck source=scripts/flow/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "使い方: bash scripts/flow/issue-finish.sh <issue番号> [<task番号>]"
N="$1"

labels="$(issue_labels "$N")"
kind="$(kind_of "$labels")"
[ -n "$kind" ] || die "#$N が種類ラベルを持たない（labels=$labels）"

head2 "#$N [$kind] $(issue_title "$N") を完了する"

# ── 段 1. task 番号 ─────────────────────────────────────────────
TASK="${2:-}"
[ -n "$TASK" ] || TASK="$(task_of "$N")"
say "  ..   ブランチの番号: $TASK"
# ★ 完了時の出力（通常経路・再入経路の 2 箇所）。親 task があれば task-run へ、無ければ区切り。
#   述語は「$TASK が task ラベルを持つか」（task-run.sh と同じ）。`$TASK = $N` では小タスクで誤る
finish_next() {
  if has_label "$(issue_labels "$TASK")" task; then
    next "$1" "" "  次: bash scripts/flow/task-run.sh $TASK（次の段へ進む）"
  fi
  next_final "$1" "" "$(handoff_steps "$TASK" -)"
}

MAIN="$(main_repo)"
# ★ マージの呼び先は**メインリポジトリ側**を指す（自分の置き場を消す経路があるため）。
#   env で差し替えない（`MERGE_CMD=true` の 1 語でマージせずに close できてしまう。
#   quality-check.sh を差し替え不可にしたのと同じ理由）。テストは砂場に scripts/ を
#   コピーして走らせるので、砂場側の偽物が使われる
MERGE_CMD="$MAIN/scripts/flow/commit.sh"
# ★ **まだメインリポジトリに無い場合だけ、この worktree の版を使う**。
#   commit.sh 自身を入れる PR では main にファイルが無く、exit 127 になる（鶏と卵）。
#   Linux は実行中のファイルを消しても open fd が生きるので、worktree が消える経路でも動く。
if [ ! -f "$MERGE_CMD" ]; then
  MERGE_CMD="$REPO_ROOT/scripts/flow/commit.sh"
  say "  ★    メインリポジトリに flow/commit.sh がまだ無いので、この worktree の版を使う"
fi
readonly MERGE_CMD

# ── 段 1.5. ★ 再入だけを許す経路（マージ後に close が落ちた場合）────
# worktree が消えた後は main で実行する。段 2 の check_branch は必ず落ちるので、その前に置く。
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || die "detached HEAD では実行できない"
# ★ `case` のパターンに変数を置くと `|` が選択肢にならない（`main|master` という 1 つの文字列になる）
if [[ "$BRANCH" =~ ^($PROTECTED_BRANCHES)$ ]]; then
    head2 "既定ブランチ（$BRANCH）で実行された。再入かどうかを見る"
    check merged "$N" || next_fail \
      "#$N の作業は既定ブランチに入っていない。**ブランチ $BRANCH では完了できない。**" \
      "" \
      "  1. bash scripts/flow/issue-start.sh $N で作業場所へ移る" \
      "  2. 作業して PR を作り、その worktree の中でこのスクリプトを呼ぶ"
    say "  ok   マージは既に済んでいる（issue だけ open で残っている）"
    if [ "$(issue_state "$N")" = CLOSED ]; then
      say "  --   #$N も既に closed。やることは無い"; exit 0
    fi
    # ★ マージの確認だけで close しない。マージ済みの PR の本文（/review・仕様整合）と成果物を見る
    rrc=0; rout="$(check reentry "$N" "$kind" 2>&1)" || rrc=$?
    printf '%s\n' "$rout"
    [ "$rrc" = 0 ] || gate_stop "$TASK" "#$N [$kind] の再入（マージ済みの PR の /review・仕様整合・成果物）が揃っていない" \
      "$rout" "bash scripts/flow/issue-finish.sh $N $TASK" "$(merge_check_hints "$N" "$TASK")" ""
    gh issue comment "$N" --body "## 完了（再入）

マージは既に済んでおり、close だけが残っていた（\`bash scripts/check-discipline.sh reentry $N $kind\` が PASS）。" \
      >/dev/null || die "gh issue comment が失敗した"
    gh issue close "$N" --reason completed >/dev/null || die "gh issue close が失敗した"
    finish_next "#$N を close した（再入経路）。"
fi

# ── 段 2. マージ直前の検査（★ 品質チェックより先。述語は check-discipline.sh が単一情報源）──
mrc=0; mout="$(check merge "$N" "$kind" "$TASK" 2>&1)" || mrc=$?
printf '%s\n' "$mout"
[ "$mrc" = 0 ] || gate_stop "$TASK" "#$N [$kind] のマージ直前の検査（ブランチ・Refs・/review・仕様整合）が通らない" \
  "$mout" "bash scripts/flow/issue-finish.sh $N $TASK" "$(merge_check_hints "$N" "$TASK")" ""

# ── 段 3. 未回答の QA ─────────────────────────────────────────
head2 "未回答の QA"
# ★ 置き場所は scripts/qa/qa-dir.sh が解決する（既定値の単一情報源は scripts/qa/config.py）
QA_REL="$(bash "$REPO_ROOT/scripts/qa/qa-dir.sh")" || die "scripts/qa/qa-dir.sh が QA の置き場所を解決できない"
case "$QA_REL" in /*) QA_DIR="$QA_REL";; *) QA_DIR="$REPO_ROOT/$QA_REL";; esac
if [ ! -f "$QA_DIR/questions.jsonl" ]; then
  # ★ 「ファイルが無い」で落とさない（恒偽になる）。省いたことは黙らない
  say "  --   $QA_DIR/questions.jsonl が無いので検査を省いた（未回答 0 件として扱う）"
else
  # ★ id の差集合を自分で実装しない。実体は scripts/qa/store.py の unanswered
  #   get_unanswered_questions()（散文の重複が既に 3 箇所あるので 5 個目を作らない）
  unanswered="$(PYTHONPATH="$REPO_ROOT/scripts" python3 -c '
import sys
from pathlib import Path
from qa.store import QAStore
qs = QAStore(Path(sys.argv[1])).get_unanswered_questions()
print(len(qs))
for q in qs:
    print(f"    未回答: {q.id} {q.question[:60]}", file=sys.stderr)
' "$QA_DIR" )" || die "未回答 QA の計数が失敗した（scripts/qa/store.py）"
  # ★ 数値以外が返ったら「検査が壊れた」として落とす（`[: integer expression expected` で
  #   無言終了すると、段 3 の失敗と QA の未回答が区別できない）
  [[ "$unanswered" =~ ^[0-9]+$ ]] \
    || die "未回答 QA の件数が数値でない（scripts/qa/store.py の出力: '${unanswered:0:80}'）"
  if [ "$unanswered" -gt 0 ]; then
    next_fail \
      "#$N: 未回答の QA が $unanswered 件ある。" \
      "" \
      "  1. 各質問に対して user-action ラベル付きのフォローアップ issue を作る" \
      "     bash scripts/flow/issue-create.sh --type docs --title \"[QA] <id>: <要約>\" \\" \
      "       --extra-label user-action" \
      "  2. その後もう一度このスクリプトを呼ぶ"
  fi
  say "  ok   未回答の QA は 0 件"
fi

# ── 段 4. 仕様ファイルのステータス ─────────────────────────────
head2 "仕様ファイルのステータス"
spec_found=0; spec_ok=0; spec_file=""
for f in "$REPO_ROOT/.spec/issues/$N"-*.md; do
  [ -e "$f" ] || continue
  # ★ check-discipline-predicates.sh の check_spec_file と同じ除外
  case "$f" in *-auto-decisions*) continue;; esac
  spec_found=1; spec_file="$f"
  body="$(cat "$f")"
  [[ "$body" =~ ステータス:[[:space:]]*completed ]] && { spec_ok=1; break; }
done
if [ "$spec_found" = 0 ]; then
  say "  --   .spec/issues/$N-*.md が無いので検査を省いた（spec 段以外は持たない）"
elif [ "$spec_ok" = 0 ]; then
  next_fail \
    "#$N: 仕様ファイル $spec_file のメタ情報が完了になっていない。" \
    "" \
    "  - 'ステータス: completed' にする（'完了日: YYYY-MM-DD'（JST）も足す）" \
    "  - ★ スクリプトは書き換えない（検査する側が対象を作ると恒真になる）"
else
  say "  ok   $spec_file は ステータス: completed"
fi

# ── 段 5. 品質チェック（★ 契約から落とさない）──────────────────
# 境界を引き直すときに落とすと、
# issue-finish.sh を直接呼ぶだけで lint・テストを通さずマージへ到達できる
run_quality "$kind"

# ── 段 6. 還流候補（出力するだけ。止めない）──────────────────────
head2 "還流候補（テンプレート由来パスの変更）"
DETECT="$REPO_ROOT/scripts/template-contribute-detect.sh"
if [ -x "$DETECT" ] || [ -f "$DETECT" ]; then
  bash "$DETECT" || say "  --   検出器が非ゼロで終わった（無視して続行する）"
else
  say "  --   $DETECT が無いので省いた"
fi

# ── 段 7. PR 番号と worktree のパス（★ cd より前に、worktree の中で）──
head2 "PR と worktree を解決する"
WORKTREE="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"

# ★ 解決は lib.sh の open_pr_for が単一情報源（commit.sh と同じ述語を使う）
PR="$(open_pr_for "$BRANCH" "どちらを閉じるかを決めてから呼び直すこと")"

MERGED_DONE=0
if [ -z "$PR" ]; then
  # ★ 枝を子 issue 間で使い回すと前の段の merged な PR も返る。本文に Refs #N（Closes / Fixes / Resolves も可）を持つものだけ数える
  prs="$(gh_json "merged な PR の取得" \
          gh pr list --head "$BRANCH" --state merged --json number --jq '.[].number')"
  merged=""; for p in $prs; do
    b="$(gh_json "PR #$p の本文の取得" gh pr view "$p" --json body -q .body)"
    if [[ "${b,,}" =~ (^|[^a-z])(refs|closes|fixes|resolves):?[[:space:]]*#${N}([^0-9]|$) ]]; then merged="$p"; break; fi
  done
  if [ -n "$merged" ]; then
    # ★ 再入（マージ済み・issue は open）。ここで「PR を作れ」と言うのは誤り
    say "  ok   マージは既に済んでいる（PR $merged）。close と報告だけ行う"
    MERGED_DONE=1
  else
    next_fail \
      "#$N: ブランチ $BRANCH に #$N の PR が無い（merged な PR は本文に 'Refs #$N' を持つものだけ数える）。" \
      "" \
      "  1. git push -u origin $BRANCH" \
      "  2. gh pr create で PR を作る。**本文に 'Refs #$N' と '## /review 結果' を書く**" \
      "     （このスクリプトは PR を作らない。判定はモデルが書く）" \
      "  3. その後もう一度このスクリプトを呼ぶ"
  fi
else
  say "  ok   PR #$PR / worktree $WORKTREE"
fi

# ── worktree を消すか（★ #N 自身を除いて数える）─────────────────
# ★ 数える相手は「この worktree を共有している他の open な issue」＝ #$TASK の open な子。
#   親が task なら $TASK はその task、そうでなければ $TASK = #N なので #N 自身の子（小タスク。issue-branch.sh が作る）
PASS_WT=""
owner="$TASK"
others=0
for k in $(sub_issues_open "$owner"); do
  [ "$k" = "$N" ] && continue   # ★ #N はまだ close していない（段 10 で閉じる）
  others=$((others + 1))
done
if [ "$others" -gt 0 ]; then
  say "  ..   #$owner に open な子が $others 件残っている → worktree は残す"
elif [ "$WORKTREE" = "$MAIN" ]; then
  # ★ メインリポジトリのパスを渡してはいけない。flow/commit.sh の段 8 は
  #   渡されたパスのブランチを remote / local ごと削除する。commit.sh 側にも
  #   `[ "$WT" != "$MAIN" ] || die` があるが、**呼ぶ側でも止める**（二重にする）
  say "  ..   メインリポジトリで実行されている → worktree パスは渡さない"
else
  say "  ..   #$owner の子はこれで最後 → worktree とブランチを消す"
  PASS_WT="$WORKTREE"
fi

# ── 段 8. マージ（★ **worktree に居たまま呼ぶ**。commit.sh が自分で cd する）──
#   check-discipline.sh merge の 3 述語は現在の HEAD / ブランチを見るので、
#   ここで先に cd すると commit.sh 側の検査が必ず落ちる
merge_rc=0
if [ "$MERGED_DONE" = 0 ]; then
  head2 "マージ（$MERGE_CMD merge $N $TASK${PASS_WT:+ $PASS_WT}）"
  if [ -n "$PASS_WT" ]; then
    bash "$MERGE_CMD" merge "$N" "$TASK" "$PASS_WT" || merge_rc=$?
  else
    bash "$MERGE_CMD" merge "$N" "$TASK" || merge_rc=$?
  fi
fi

# ── 段 9. メインリポジトリへ移る（★ 戻ってきたら**即座に**。CWD が消えていても
#   絶対パスへの cd は成功する。先に git / gh を呼ぶと exit 128 になる）──
cd "$MAIN" || die "メインリポジトリ $MAIN へ移れない"
head2 "メインリポジトリへ移った（$MAIN）"

# ★ 終了コードで文言を分ける（10 = マージは済んだが後片付けで失敗）。
#   「マージが失敗した」と嘘を書くと、#N が open のまま残り再入経路も誤誘導する
if [ "$merge_rc" = "$POST_MERGE_FAILED" ]; then
  say "!!! マージは済んでいる（PR #$PR は squash merge された）。失敗したのは後片付けだけ"
  say "  ..   どこで止まったかは上の !!! 行を見ること。残りうるものと片付け方:"
  say "  ..     既定ブランチが未更新 → git -C $MAIN pull --ff-only origin $DEFAULT_BRANCH"
  say "  ..     worktree が残っている → bash scripts/worktree-relative.sh remove $WORKTREE --force"
  say "  ..     ブランチが残っている   → git branch -D $BRANCH / git push origin --delete $BRANCH"
  say "  ..   マージし直す必要は無い。#$N はこの後 close する"
  say "  ..   引き継ぎを書くなら、残っている後片付けを『未解決の問い』に書く"
elif [ "$merge_rc" != 0 ]; then
  die "マージが失敗した（exit $merge_rc）。上の出力を見ること"
fi

# ── 段 9b. ★ 枝を既定ブランチに合わせ直す ─────────────────────────
# 枝を残す場合だけ。**残さないなら消すので合わせる意味が無い。**
# ★ マージの後なので、失敗しても「マージが失敗した」とは書かない（close まで進む）
if [ "$MERGED_DONE" = 0 ] && [ "$merge_rc" = 0 ] \
   && [ -z "$PASS_WT" ] && [ "$WORKTREE" != "$MAIN" ]; then
  head2 "枝を既定ブランチに合わせ直す（次の子が衝突しないように）"
  pr_head="$(gh pr view "$PR" --json headRefOid -q .headRefOid 2>/dev/null || true)"
  realign_branch "$WORKTREE" "$BRANCH" "$pr_head" || {
    say "  ..   **マージは済んでいる。** 次の子で squash merge が衝突する可能性がある"
    say "  ..   手で直す: まず git -C $WORKTREE diff origin/$DEFAULT_BRANCH HEAD --stat と"
    say "  ..     git -C $WORKTREE log --oneline ${pr_head:-<PR の head>}..HEAD で、PR に入っていないコミットが無いことを確かめる。"
    say "  ..     無いときだけ git -C $WORKTREE reset --hard origin/$DEFAULT_BRANCH && git -C $WORKTREE push --force-with-lease origin $BRANCH"
  }
fi

# ── 段 10. 完了報告と close ──────────────────────────────────────
head2 "完了報告と close"
if [ "$(issue_state "$N")" = CLOSED ]; then
  say "  --   #$N は既に closed"
else
  # ★ 実際に起きたことを書く。**`MERGED_DONE=1` のときは削除も走っていない**
  #   （段 9 を飛ばしているので、PASS_WT が立っていても消えていない）
  if [ "$MERGED_DONE" = 1 ]; then
    merge_line="既に済んでいた（このスクリプトはマージを呼んでいない）"
    wt_line="触っていない"
  else
    merge_line="PR #$PR を squash merge"
    if [ "$merge_rc" = "$POST_MERGE_FAILED" ]; then
      # ★ 失敗したのが worktree とは限らない（既定ブランチの更新かもしれない）。
      #   実行時の出力にしか無いので、**この欄で断定しない**
      wt_line="**後片付けのどこかが失敗した**（既定ブランチの更新 / worktree の削除 / ブランチの削除 のいずれか。
  git worktree list と git branch -a で現状を確かめて手で片付けること）"
    elif [ -n "$PASS_WT" ]; then wt_line="削除した（$PASS_WT。#$owner の最後の子）"
    else wt_line="残した（#$owner に open な子がある、またはメインリポジトリで実行された）"; fi
  fi
  # ★ 走らせたか省いたかを記録にも書く（端末だけ正直で記録が嘘、をなくす）
  if [ "$QUALITY_RAN" = 1 ]; then quality_line="通過（scripts/quality-check.sh）"
  else quality_line="直前に同じ内容で通っているので省いた（lib.sh の記録と一致）"; fi
  gh issue comment "$N" --body "## 完了

- マージ直前の検査: 通過（bash scripts/check-discipline.sh merge $N $TASK）
- 品質チェック: $quality_line
- マージ: $merge_line
- worktree: $wt_line" \
    >/dev/null || die "gh issue comment が失敗した"
  gh issue close "$N" --reason completed >/dev/null || die "gh issue close が失敗した"
  say "  ok   #$N を close した"
fi

finish_next "#$N を完了した。"
