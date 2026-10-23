#!/usr/bin/env bash
#
# scripts/flow/issue-{create,start,branch,finish}.sh の自己検証（#506）。
#
# ★ **検査が「落ちること」を、項目ごとに単独で確かめる。**
#   存在だけを見る検査は恒真になり（.spec/known-issues.md KI-008）、
#   規律を完璧に守っても落ちる検査は恒偽になる（KI-013）。**両方を見る。**
#
# 仕様: .spec/issues/504-issue-scripts.md §7（この並びのまま実装している）
#
# 実行:  ./tests/test_issue_flow.sh
# 終了:  0 全て成立 / 1 いずれか不成立
#
# ★ **砂場に scripts/ をコピーして、そのコピーを実行する**（§7 冒頭）。
#   REPO_ROOT は lib.sh の 2 つ上なので砂場を指し、$QUALITY / $CHECK / $MERGE_CMD が
#   すべて砂場側の偽物になる（本物は readonly で env 差し替え不可）。
# ★ `| grep -q` / `| head ` を使わない（#454）。`grep -c` と [[ =~ ]] を使う。
#
# ── 偽 gh の応答表（§7 冒頭の要求。fixture は $SB/issues.txt）──────────────────
#   行の形: 番号:ラベル列:状態:題名:parent=<番号|空>
#
#   gh repo view                      → x/y
#   gh label list --limit 200         → $GH_LABELS（既定は全ラベル。減らすと存在確認が落ちる）
#   gh issue create …                 → URL（番号は $GH_NEW。既定 4242）。**引数を $SB/gh.log に記録**
#   gh issue list …                   → 9999（★ URL から取らない実装を捕まえるための別番号）
#   gh issue view N --json labels     → ラベル列 / state → 状態 / parent → 親番号 / title,body → 題名+本文
#   gh issue comment N / close N      → 0。**$SB/gh.log と $SB/gh-body.log に記録**
#   gh api …/sub_issues               → 子番号（`select(.state=="open")` を**再現する**）
#   gh api …/issues/N                 → 内部 id 999888
#   gh pr list --head V --state S     → $GH_PR（既定 77）。**V が $GH_PR_HEAD と一致し、
#                                        S が $GH_PR_STATE（既定 open）と一致したときだけ**返す
#                                        （--head の有無だけで分けると cd 後に引き直す実装が素通りする）
#   gh pr view --json body            → `## /review 結果` 付き本文。$GH_PR_NO_REVIEW=1 で見出しを消す。
#                                        末尾に PR ごとの $GH_PR_CLOSES_<番号>、無ければ $GH_PR_CLOSES の行
#                                        （既定 `Refs #901`）を足す（#715。番号を無視すると 1 本目だけ見る実装が素通りする）
#   GH_NOISE=1                        → すべての呼び出しで stderr に 1 行出す（本物の更新通知の再現）

set -uo pipefail
# ★ 起動のたびに読まれる初期化ファイルを切る（bash 1 回の起動が 275 ms → 14 ms）
unset BASH_ENV ENV
# ★ 品質ゲートの中から走ると QUALITY_* を継承する。記録の鍵の検査が親の値で変わらないよう切る
unset QUALITY_FULL_SCAN QUALITY_SCOPE QUALITY_BASE_BRANCH

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly FLOW="$REPO_ROOT/scripts/flow"

PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }
# ★ `A && ok … || ng …` は使わない（shellcheck SC2015。A が真でも ok が失敗すると ng も走る）。
#   `COND; judge $?` も使わない（SC2319。`[ ]` の後の `$?` は上書きされやすい）。
#   **判定はすべて if 文で書く。**

# コメント行を落とした本文（実装が意図的に書いている「使わない」の注記を拾わないため）
code_of() { grep -vE '^[[:space:]]*#' "$1"; }
count_in_code() {  # count_in_code <ファイル> <ERE>
  # ★ `-e` で渡す（パターンが `--foo` で始まってもオプションと解釈させない）
  local body; body="$(code_of "$1")"
  printf '%s' "$body" | grep -cE -e "$2" || true
}

# ★ mktemp の失敗を見る。見ないと SANDBOX="" のまま進み、`mkdir -p "$SANDBOX/bin"` が
#   **/bin**、`rm -rf "$R"` が **/repo** を指す（段 1 は ${SANDBOX:?} で守っている）
SANDBOX="$(mktemp -d)" || { echo "mktemp -d が失敗した" >&2; exit 1; }
[ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] || { echo "砂場を作れない" >&2; exit 1; }
export SB="$SANDBOX"
export FAKE_GH="$REPO_ROOT/tests/lib/fake_gh.py" FAKE_GH_DIR="$SANDBOX/gh" FAKE_GH_ROWS="$SANDBOX/issues.txt"
trap 'rm -rf "${SANDBOX:?}"' EXIT
mkdir -p "${SANDBOX:?}/bin"

echo "=== flow/issue-*.sh の自己検証（#506）==="

# ══════════════════════════════════════════════════════════════════
# §7-1 静的な性質（★ 4 本を固定列挙せず glob で回す）
# ══════════════════════════════════════════════════════════════════
echo "--- §7-1 静的な性質 ---"

# ★ 品質ゲートの範囲（quality-check.sh の FLOW_FILES）に、flow が呼ぶ scripts/ のファイルが全部入っているか。
#   漏れていると、そのファイルだけを変えた PR で flow のテストが走らず、配線切れがマージされる
flow_files="$(sed -n "s/^FLOW_FILES='\(.*\)'$/\1/p" "$REPO_ROOT/scripts/quality-check.sh")"
if [ -z "$flow_files" ]; then ng "quality-check.sh に FLOW_FILES が無い（flow のテストが品質ゲートに登録されていない）"
else
  missing=""
  while IFS= read -r ref; do
    [ -e "$REPO_ROOT/$ref" ] || continue
    [[ "$ref" =~ $flow_files ]] || missing="$missing $ref"
  done < <(grep -ohE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)' "$FLOW"/*.sh "$REPO_ROOT"/scripts/check-discipline* | sort -u)
  if [ -z "$missing" ]; then ok "flow が呼ぶ scripts/ のファイルは全部 FLOW_FILES に入っている"
  else ng "FLOW_FILES に無い:$missing"; fi
  for t in issue_flow commit_flow quick_flow task_run; do
    if [ "$(grep -cF "for t in issue_flow commit_flow quick_flow task_run" "$REPO_ROOT/scripts/quality-check.sh")" -gt 0 ] \
       && [[ "tests/test_$t.sh" =~ $flow_files ]]; then ok "quality-check.sh が test_$t.sh を走らせる"
    else ng "quality-check.sh が test_$t.sh を走らせていない"; fi
  done
fi

for f in "$FLOW"/*.sh; do
  n="$(wc -l <"$f")"
  if [ "$n" -le 300 ]; then ok "$(basename "$f") は $n 行（上限 300）"
  else ng "$(basename "$f") は $n 行で上限 300 を超える"; fi
  # #454: pipefail 下で `| grep -q` / `| head ` は生産者を SIGPIPE で殺す
  if [ "$(count_in_code "$f" '\|[[:space:]]*(grep -q|head )')" -gt 0 ]; then  # pipefail-grep-q:allow 検出対象の綴りそのもの
    ng "$(basename "$f") に #454 の禁止形がある"
  else ok "$(basename "$f") に #454 の禁止形が無い"; fi
done

for s in issue-create issue-start issue-branch issue-finish; do
  f="$REPO_ROOT/.claude/skills/$s/SKILL.md"
  n="$(wc -l <"$f")"
  if [ "$n" -le 50 ]; then ok "$s/SKILL.md は $n 行（上限 50）"
  else ng "$s/SKILL.md は $n 行で上限 50 を超える"; fi
  # ★ 正規表現は段 1（tests/test_task_run.sh:83）と同一。
  #   `bash scripts/flow/*.sh` の 1 行は §6 が必須とするので禁止しない
  if [ "$(grep -cE '^\s*(gh |git |\[ |bash scripts/check-discipline|check |exit|if )' "$f" || true)" -gt 0 ]; then
    ng "$s/SKILL.md に判定・手順の bash が残っている"
  else ok "$s/SKILL.md に判定の bash が無い"; fi
  if [ "$(grep -cE '^```python' "$f" || true)" -gt 0 ]; then
    ng "$s/SKILL.md に python ブロックが残っている"
  else ok "$s/SKILL.md に python ブロックが無い"; fi
  if [ "$(grep -cE '^description:' "$f" || true)" -gt 0 ]; then
    ok "$s/SKILL.md に frontmatter の description がある"
  else ng "$s/SKILL.md に description が無い（スキルの発見に使われる）"; fi
done

TR="$FLOW/task-run.sh"
if [ "$(count_in_code "$TR" '既存のスキル名')" -eq 0 ]; then ok "task-run.sh に「既存のスキル名である」の注記が無い"
else ng "task-run.sh に「既存のスキル名である」が残っている"; fi
# ★ 段 2 の時点での検査。段 3 が task-run.sh から直接呼ぶ形を採るなら段 3 が更新する（§1-2）
if [ "$(count_in_code "$TR" 'check-discipline\.sh merge')" -eq 0 ]; then ok "task-run.sh に check-discipline.sh merge の文字列が無い（呼び出しを 2 箇所に置かない）"
else ng "task-run.sh に check-discipline.sh merge が残っている"; fi
if [ "$(count_in_code "$TR" 'flow/issue-start\.sh')" -gt 0 ]; then ok "task-run.sh が issue-start.sh を指す"
else ng "task-run.sh が issue-start.sh を指さない"; fi
if [ "$(count_in_code "$TR" 'flow/issue-finish\.sh')" -gt 0 ]; then ok "task-run.sh が issue-finish.sh を指す"
else ng "task-run.sh が issue-finish.sh を指さない"; fi
# gh issue create を含むのは issue-create.sh だけ（★ コメントを落として数える）
creators=0
for f in "$FLOW"/*.sh; do
  [ "$(count_in_code "$f" 'gh issue create')" -gt 0 ] || continue
  creators=$((creators + 1))
  [ "$(basename "$f")" = issue-create.sh ] || ng "$(basename "$f") が gh issue create を直に呼んでいる"
done
if [ "$creators" -eq 1 ]; then ok "gh issue create を含む flow は 1 本だけ（issue-create.sh）"
else ng "gh issue create を含む flow が $creators 本ある"; fi
if [ "$(count_in_code "$FLOW/issue-start.sh" '--relative-paths')" -eq 0 ]; then ok "issue-start.sh に --relative-paths が無い（INV-001）"
else ng "issue-start.sh が --relative-paths を付けている"; fi
if [ "$(count_in_code "$FLOW/issue-start.sh" '--add-label')" -eq 0 ]; then ok "issue-start.sh に --add-label が無い（状態ラベルを付けない）"
else ng "issue-start.sh が状態ラベルを付けている"; fi
# ★ 段 3: cd "$MAIN" は $MERGE_CMD の呼び出しより**後**にある（534 §2-3 / §6-5）
# shellcheck disable=SC2016  # $MERGE_CMD / $MAIN は**被検査ファイルの中の綴り**なので展開させない
mc_line="$(grep -n 'bash "\$MERGE_CMD"' "$FLOW/issue-finish.sh" | sed -n '1s/:.*//p')"
# shellcheck disable=SC2016
cd_line="$(grep -n 'cd "\$MAIN"' "$FLOW/issue-finish.sh" | sed -n '1s/:.*//p')"
if [ -n "$mc_line" ] && [ -n "$cd_line" ] && [ "$cd_line" -gt "$mc_line" ]; then
  ok "issue-finish.sh: cd \"\$MAIN\" が \$MERGE_CMD の呼び出しより後（:$mc_line → :$cd_line）"
else
  ng "issue-finish.sh: cd \"\$MAIN\"（:${cd_line:-?}）が \$MERGE_CMD（:${mc_line:-?}）より前にある。check merge が必ず落ちる"
fi
if [ "$(count_in_code "$FLOW/issue-finish.sh" 'scripts/commit-merge\.sh')" -eq 0 ]; then
  ok "issue-finish.sh に旧マージスクリプトへの参照が無い（段 3 で flow/commit.sh に移した）"
else ng "issue-finish.sh がまだ旧マージスクリプトを指している"; fi
if [ "$(count_in_code "$FLOW/lib.sh" '2>&1')" -eq 0 ]; then ok "lib.sh が gh の stderr を値に混ぜていない（#505 の回帰）"
else ng "lib.sh に 2>&1 がある（gh の stderr が値を壊す）"; fi
# ★ `\|` は grep -E ではリテラルの縦棒。つまり「BRANCH_TYPES の値をそのまま写した並び」を探す
#   （交替と読むと issue-start.sh の `spec)` に当たって恒偽になる）。
#   検査は 1 本ではなく **flow 全体**に掛ける（lib.sh が読む形に揃っていること）
copied=0
for f in "$FLOW"/*.sh; do
  [ "$(count_in_code "$f" 'feature\|survey\|spec')" -eq 0 ] && continue
  copied=$((copied + 1)); ng "$(basename "$f") が BRANCH_TYPES を書き写している（単一情報源から外れる）"
done
if [ "$copied" -eq 0 ]; then ok "flow のどれも BRANCH_TYPES の値を書き写していない（predicates から読む）"; fi
if [ "$(count_in_code "$REPO_ROOT/scripts/check-skill-labels.sh" "scripts/flow")" -gt 0 ]; then ok "check-skill-labels.sh の走査対象に scripts/flow が入っている"
else ng "check-skill-labels.sh が scripts/flow を走査しない（ラベル検査の網が外れる）"; fi
# ★ #528: /task-start の task 作成は --body-file を渡す（issue-create.sh は本文なしの task で必ず落ちる）
ts_line="$(grep -E 'Skill\(skill="issue-create", args="--type task ' "$REPO_ROOT/.claude/skills/task-start/SKILL.md" || true)"
if [ -n "$ts_line" ] && [[ "$ts_line" == *--body-file* ]]; then ok "task-start/SKILL.md の task 作成が --body-file を渡す（#528）"
else ng "task-start/SKILL.md の task 作成に --body-file が無い（documented な経路が必ず落ちる。#528）"; fi
# ★ 接頭辞の表（lib.sh の branch_prefix）の値の集合 ＝ predicates の BRANCH_TYPES（bug は旧来の綴りとして BRANCH_TYPES にだけ残す）
prefixes="$(bash -c '. "$1"; for k in $DEFAULT_ORDER $EXTRA_ORDER; do branch_prefix "$k"; echo; done' _ "$FLOW/lib.sh" 2>/dev/null | sort -u | tr '\n' ' ')"
types="$(sed -n 's/^readonly BRANCH_TYPES="\(.*\)"$/\1/p' "$REPO_ROOT/scripts/check-discipline-predicates.sh" | tr '|' '\n' | grep -vx bug | sort -u | tr '\n' ' ')"
if [ -n "$prefixes" ] && [ "$prefixes" = "$types" ]; then ok "branch_prefix の値の集合が BRANCH_TYPES（bug を除く）と一致する（$prefixes）"
else ng "branch_prefix の値（$prefixes）と BRANCH_TYPES（$types）が食い違う"; fi
if [ -z "$(bash -c '. "$1"; branch_prefix unknown-kind' _ "$FLOW/lib.sh" 2>/dev/null)" ]; then ok "表に無い種類は空（既定の接頭辞に丸めない）"
else ng "表に無い種類に接頭辞を返している"; fi
# ══════════════════════════════════════════════════════════════════
# 砂場（scripts/ をコピーし、外部コマンドは偽物にする）
# ══════════════════════════════════════════════════════════════════
make_gh() {
  cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# ★ §4 のゲートが使う呼び出し（本文・コメント・lastEditedAt・コメントの追加）は
#   issue ごとの状態を持つ tests/lib/fake_gh.py に回す
case "$*" in "issue view "*" --json body,comments,createdAt"*|"api graphql"*) exec python3 -B "$FAKE_GH" "$@";; esac
if [ "$1 $2" = "issue comment" ]; then python3 -B "$FAKE_GH" "$@" || exit 1; fi
# 偽の gh。$SB/issues.txt を引く。行の形: 番号:ラベル列:状態:題名:parent=<番号|空>
f="$SB/issues.txt"
row() { grep -E "^$1:" "$f" || true; }
# ★ 本物の gh は更新通知などを stderr に出す。GH_NOISE=1 でそれを再現する
[ -z "${GH_NOISE:-}" ] || echo "gh: A new release of gh is available" >&2
case "$1 $2" in
  "repo view")    echo "x/y"; exit 0;;
  "label list")   echo "${GH_LABELS:-epic,task,survey,spec,feature,validation,experiment,bug,docs,refactor,chore,review-integrity,user-action,blocked}"; exit 0;;
  "issue create") printf 'create %s\n' "$*" >> "$SB/gh.log"
                  echo "https://github.com/x/y/issues/${GH_NEW:-4242}"; exit 0;;
  "issue list")   echo "9999"; exit 0;;   # ★ URL から取らない実装を捕まえるための別番号
esac
if [ "$1" = issue ] && { [ "$2" = comment ] || [ "$2" = close ]; }; then
  printf '%s %s\n' "$2" "$3" >> "$SB/gh.log"
  printf '%s\n' "$*" >> "$SB/gh-body.log"
  exit 0
fi
if [ "$1" = issue ] && [ "$2" = view ]; then
  r="$(row "$3")"; [ -n "$r" ] || { echo "not found" >&2; exit 1; }
  IFS=: read -r _ labels state title parent <<< "$r"
  case "$*" in
    *labels*)    echo "$labels";;
    *state*)     echo "$state";;
    *parent*)    echo "${parent#parent=}";;
    *title,body*) echo "$title"; echo "本文";;
    *title*)     echo "$title";;
    *createdAt*) echo "2020-01-01T00:00:00Z";;
    *) echo "$title";;
  esac
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = list ]; then
  head=""; state="open"
  while [ $# -gt 0 ]; do
    case "$1" in --head) head="${2:-}";; --state) state="${2:-}";; esac; shift
  done
  # ★ --head の**値**で応答を変える（有無だけで分けると cd 後に取り直す実装が素通りする）
  # ★ 既定を空にしない。空にすると「--head を渡さない実装」とも一致してしまう
  if [ "$state" = "${GH_PR_STATE:-open}" ] && [ "$head" = "${GH_PR_HEAD:-__unset__}" ]; then
    printf '%s\n' ${GH_PR:-77}
  fi
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  case "$*" in *"--json state"*) [ "${GH_PR_STATE:-open}" = merged ] && echo MERGED || echo OPEN; exit 0;; esac
  if [ -n "${GH_PR_NO_REVIEW:-}" ]; then echo "## 変更概要"; else
    echo "## /review 結果"; echo ""; echo "| x | ok |"; fi
  printf '%s\n' "${GH_PR_CONFORM-$'## 仕様整合\n\n- goal 書き換え: なし\n- positive control: 砂場で検出できた\n- matched-engineering: 揃えた\n- 格付け: verified-negative'}"
  v="GH_PR_CLOSES_${3:-}"; v="${v//[^A-Za-z0-9_]/_}"; echo "${!v-${GH_PR_CLOSES-Refs #901}}"
  exit 0
fi
if [ "$1" = api ]; then
  case "$2" in
    *"/sub_issues")
      p="$(echo "$2" | sed -E 's|.*/issues/([0-9]+)/sub_issues|\1|')"
      only_open=0; case "$*" in *'state=="open"'*) only_open=1;; esac
      while IFS=: read -r n l st t pa; do
        [ "$pa" = "parent=$p" ] || continue
        [ "$only_open" = 1 ] && [ "$st" != OPEN ] && continue
        printf '%s\n' "$n"
      done < "$f"
      exit 0;;
    *) echo "999888"; exit 0;;   # 内部 id
  esac
fi
exit 0
STUB
  chmod +x "$SANDBOX/bin/gh"
}

fixture() { rm -rf "${FAKE_GH_DIR:?}"; printf '%s' "$1" > "$SANDBOX/issues.txt"; }

# 既定の fixture:
#   800 epic / 801 sub-epic(親 800) / 900 task(親 800)
#   901 spec(親 900, OPEN) / 902 feature(親 900, OPEN) / 910 bug(親なし) / 920 review-integrity
DEFAULT_FIXTURE='800:epic:OPEN:親epic:parent=
801:epic:OPEN:sub-epic:parent=800
900:task:OPEN:task:parent=800
901:spec:OPEN:spec段:parent=900
902:feature:OPEN:feature段:parent=900
910:bug:OPEN:単発:parent=
920:review-integrity:OPEN:報告:parent=
'

setup_sandbox() {
  local R="$SANDBOX/repo"
  rm -rf "$R"; mkdir -p "$R/scripts/flow" "$R/.spec/issues" "$R/data/shared"
  cp "$FLOW"/*.sh "$R/scripts/flow/"
  cp "$REPO_ROOT/scripts/check-discipline.sh" "$REPO_ROOT/scripts/check-discipline-predicates.sh" "$REPO_ROOT/scripts/check-discipline-gates.py" "$REPO_ROOT/scripts/check_discipline_md.py" "$R/scripts/"
  # ★ worktree の作成はこれを通す（偽物を置かない。実物で動かす）
  cp "$REPO_ROOT/scripts/worktree-relative.sh" "$R/scripts/"
  # ★ 偽物: 呼ばれたことと渡された worktree を記録する（実物は agent-skills.py 等を走らせる）
  cat > "$R/scripts/configure-agent-workflow.sh" <<'SH'
#!/usr/bin/env bash
printf 'configure-agent-workflow %s\n' "${1:-}" >> "$SB/calls.log"
SH
  # ★ issue-start.sh が共有ストアの場所を引く（#527。何に解決するかで data/shared を判定する）
  mkdir -p "$R/scripts/lib" "$R/.claude"
  cp "$REPO_ROOT/scripts/lib/shared-store.sh" "$R/scripts/lib/"
  printf '{"shared_data_path": "data/shared", "path_type": "relative"}\n' > "$R/.claude/worktree-config.json"
  cp -r "$REPO_ROOT/scripts/qa" "$R/scripts/qa"
  # 偽物（本物は readonly で env 差し替え不可なので、コピーで置き換える）
  # ★ heredoc を quoted（<<'SH'）にして、$SB 等を**偽物の中で**展開させる
  cat > "$R/scripts/quality-check.sh" <<'SH'
#!/usr/bin/env bash
printf 'quality scope=%s\n' "${QUALITY_SCOPE:-}" >> "$SB/calls.log"
exit "$(cat "$SB/quality_rc" 2>/dev/null || echo 0)"
SH
  # ★ 段 3 で実体が scripts/flow/commit.sh の merge サブコマンドに移った。
  #   設置先と引数の添字（worktree は $2 → $4）を追随させる
  cat > "$R/scripts/flow/commit.sh" <<'SH'
#!/usr/bin/env bash
printf 'merge args=%s\n' "$*" >> "$SB/calls.log"
printf 'merge cwd=%s\n' "$(pwd -P)" >> "$SB/calls.log"
rc="$(cat "$SB/merge_rc" 2>/dev/null || echo 0)"
[ "$rc" = 0 ] || exit "$rc"
# 本物と同じく worktree を消す版（$SB/merge_removes_wt が在るとき）。worktree は $4
if [ -e "$SB/merge_removes_wt" ] && [ -n "${4:-}" ]; then
  main=""
  while IFS= read -r line; do
    case "$line" in worktree\ *) main="${line#worktree }"; break;; esac
  done < <(git worktree list --porcelain)
  (cd "$main" && bash scripts/worktree-relative.sh remove "$4" --force)   # 本物（commit.sh 段 8）と同じ
fi
exit 0
SH
  cat > "$R/scripts/setup-worktree.sh" <<'SH'
#!/usr/bin/env bash
printf 'setup-worktree %s\n' "$(pwd)" >> "$SB/calls.log"
[ ! -e "$SB/setup_fail" ] || exit 1
mkdir -p data && ln -sfn ../../../data/shared data/shared
SH
  cat > "$R/scripts/template-contribute-detect.sh" <<'SH'
#!/usr/bin/env bash
[ ! -e "$SB/reflux" ] || echo "還流候補: scripts/quality-check.sh"
SH
  chmod +x "$R/scripts"/*.sh "$R/scripts/flow"/*.sh
  ( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t && echo base > a.txt && git add -A && git commit -qm base && git update-ref refs/remotes/origin/main HEAD ) >/dev/null
  rm -f "$SANDBOX/calls.log" "$SANDBOX/gh.log" "$SANDBOX/gh-body.log" "$SANDBOX/quality_rc" "$SANDBOX/setup_fail" "$SANDBOX/merge_removes_wt" "$SANDBOX/reflux"
  fixture "$DEFAULT_FIXTURE"
}

# flow <期待コード> <説明> <スクリプト> <引数...>   砂場のコピーを実行する
flow() {
  local want="$1" what="$2" script="$3"; shift 3
  local out rc
  out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" bash "$SANDBOX/repo/scripts/flow/$script" "$@" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/        /'
  fi
}
# flow_in <ディレクトリ> <期待コード> <説明> <スクリプト> <引数...>
# ★ **そのディレクトリにある copy を実行する。** 本番でも worktree の中から
#   `bash scripts/flow/...` を呼ぶので、REPO_ROOT（lib.sh の 2 つ上）は worktree になる。
#   main リポジトリ側のコピーを実行すると REPO_ROOT が main になり、
#   仕様ファイルや QA の置き場所を**別の場所で探してしまう**（実際にこの取り違えを踏んだ）
flow_in() {
  local dir="$1" want="$2" what="$3" script="$4"; shift 4
  local out rc
  out="$(cd "$dir" && PATH="$SANDBOX/bin:$PATH" bash "$dir/scripts/flow/$script" "$@" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/        /'
  fi
}
calls() { cat "$SANDBOX/calls.log" 2>/dev/null || true; }
has_call() { [ "$(calls | grep -cF "$1" || true)" -gt 0 ]; }

make_gh
setup_sandbox

# ══════════════════════════════════════════════════════════════════
# §7-2 階層の照合（§4 の表を 1 行ずつ。通す側と落とす側の両方）
# ══════════════════════════════════════════════════════════════════
echo "--- §7-2 階層の照合 ---"
create() { flow "$1" "$2" issue-create.sh "${@:3}"; }

create 0 "epic の親なし → 通る"            --type epic --title t
create 0 "epic の親が epic（2 段目）→ 通る" --type epic --title t --parent 800
create 1 "epic の 3 段目 → 落ちる"          --type epic --title t --parent 801
create 1 "task の親なし → 落ちる"           --type task --title t
create 1 "task の親が task → 落ちる"        --type task --title t --parent 900
create 1 "種類ラベルの親が epic → 落ちる"   --type feature --title t --parent 800
create 0 "種類ラベルの親が task → 通る"     --type feature --title t --parent 900
create 0 "種類ラベルの親が種類ラベル（小タスク）→ 通る" --type feature --title t --parent 901
create 0 "種類ラベルの親なし → 通る"        --type feature --title t
create 0 "review-integrity の親なし → 通る（★ 報告を丸ごと拒否する実装を落とす）" --type review-integrity --title t
create 1 "review-integrity に親を付ける → 落ちる" --type review-integrity --title t --parent 900
create 1 "種類ラベルの親が報告 issue → 落ちる"    --type feature --title t --parent 920
create 1 "未定義ラベル → 落ちる（setup-labels.sh を促す）" --type nonsense --title t
create 1 "--title が無い → 落ちる"          --type feature
create 1 "未知のオプション → 落ちる（--label の打ち間違いを黙って通さない）" --type feature --title t --lable x
# ★ task の本文は /task-start が埋める（雛形を作らせない）
create 1 "task を --body-file なしで作ると落ちる" --type task --title t --parent 800

# ★ task の親が epic → **通る**（本文は /task-start が埋めるので --body-file を与える）
BODY_TMP="$SANDBOX/task-body.md"
printf '## 目標の状態\n\nx\n' > "$BODY_TMP"
create 0 "task の親が epic → 通る（★ この行が無いと task/epic の許可を消しても緑になる）" \
  --type task --title t --parent 800 --body-file "$BODY_TMP"

# ラベル存在確認の網（§3-1 段 2。#118 の再発を実際に止めるのはここ）
GH_LABELS="epic,task" flow 1 "定義済みラベルが減ると feature で落ちる（gh label list の網）" issue-create.sh --type feature --title t --parent 900

# ══════════════════════════════════════════════════════════════════
# §7-3 番号の取り方（成功条件 5）
# ══════════════════════════════════════════════════════════════════
echo "--- §7-3 番号の取り方 ---"
out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" GH_NEW=4242 bash scripts/flow/issue-create.sh --type feature --title t --parent 900 2>/dev/null)"
if [ "$out" = "作成: #4242" ]; then
  ok "stdout は URL 側の番号 1 行だけ（gh issue list の 9999 を拾わない）"
else
  ng "stdout が '作成: #4242' でない: '$out'"
fi

# ★ gh の stderr 混入に耐えるか（#505 の回帰。混ざると kind_of が空になり die する）
GH_NOISE=1 flow 0 "gh が stderr に 1 行出しても値が壊れない（gh_json の回帰）" issue-create.sh --type feature --title t --parent 900

# ══════════════════════════════════════════════════════════════════
# §7-4 issue-start.sh
# ══════════════════════════════════════════════════════════════════
echo "--- §7-4 issue-start.sh ---"
setup_sandbox
flow 1 "epic を渡すと落ちる（worktree を持たない層）"  issue-start.sh 800
flow 1 "task を渡すと落ちる（/task-run を使う）"       issue-start.sh 900

fixture "${DEFAULT_FIXTURE//902:feature:OPEN/902:feature:CLOSED}"
flow 1 "closed な issue を渡すと落ちる"                issue-start.sh 902
fixture "$DEFAULT_FIXTURE"

flow 0 "何も無い状態 → worktree を作る"                issue-start.sh 901
WT="$SANDBOX/repo/worktrees/task900"
if [ -d "$WT" ]; then ok "作成先が <メインリポジトリ>/worktrees/task900 と一致する"
else ng "worktree が想定の場所に無い"; fi
got_branch="$(git -C "$WT" branch --show-current)"
if [ "$got_branch" = "spec/900-i901" ]; then ok "ブランチ名が spec/900-i901（種類ラベル spec → spec/）"
else ng "ブランチ名が違う: $got_branch"; fi
if has_call "setup-worktree"; then ok "setup-worktree.sh を呼ぶ（data/shared の保護）"
else ng "setup-worktree.sh を呼んでいない（成果物が worktree 削除で消える）"; fi
rm -f "$SANDBOX/calls.log"
flow 0 "2 回目は worktree も着手コメントも作らない（冪等）"  issue-start.sh 901
if has_call "setup-worktree"; then ng "2 回目も setup-worktree.sh を呼んでいる"
else ok "2 回目は setup-worktree.sh を呼ばない（symlink がある）"; fi
if [ "$(grep -cF 'comment 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -eq 1 ]; then ok "着手コメントは 1 回だけ（毎回付けると積み上がる）"
else ng "着手コメントの回数が 1 ではない"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '次にやること' || true)" -gt 0 ]; then ok "2 回目でも「次にやること」は出る（早期終了で案内を失わない）"
else ng "2 回目に案内が出ない"; fi
# ★ **worktree の中から**呼ぶ経路（種類の異なる type で）。main から呼ぶだけでは
#   「すでに task のブランチに居る」分岐（issue-start.sh:49-55）を一度も通らない
rm -f "$SANDBOX/calls.log"
flow_in "$WT" 0 "worktree の中から別の段（#902 feature）を開始しても 0（type の一致を要求しない）" \
  issue-start.sh 902
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'すでに task #900 のブランチに居る' || true)" -gt 0 ]; then
  ok "「すでに task のブランチに居る」分岐を通る（2 本目のブランチを作らない）"
else ng "その分岐を通っていない（type 一致を要求していないか確認）"; fi
if [ "$(git -C "$SANDBOX/repo" for-each-ref --format='%(refname:short)' 'refs/heads/*/900-*' \
         | grep -c . || true)" -eq 1 ]; then
  ok "task #900 のブランチは 1 本だけ（1 task = 1 ブランチ）"
else ng "task #900 のブランチが増えている"; fi

# ★ symlink を壊すと、既存 worktree でも張り直す（created フラグだと永久に抜ける）
rm -f "$WT/data/shared"; rm -f "$SANDBOX/calls.log"
flow 0 "symlink が無ければ既存 worktree でも setup-worktree.sh を呼び直す" issue-start.sh 901
if has_call "setup-worktree"; then ok "呼び直した（保護が永久に抜けない）"
else ng "呼び直していない（setup-worktree.sh の失敗が恒久化する）"; fi
# ★ setup-worktree.sh が落ちたら die する（張られないまま進ませない）
rm -f "$WT/data/shared"; : > "$SANDBOX/setup_fail"
flow 1 "setup-worktree.sh が落ちたら非ゼロ（張られないまま作業させない）" issue-start.sh 901
rm -f "$SANDBOX/setup_fail"
# ★ #527: **ダングリング**な symlink・**共有ストア以外**を指す symlink でも張り直す（`-L` だけで判定しない）
for bad in "$SANDBOX/nowhere" "$SANDBOX/bin"; do
  ln -sfn "$bad" "$WT/data/shared"; rm -f "$SANDBOX/calls.log"
  flow 0 "data/shared が $bad を指す symlink → 既存 worktree でも動く" issue-start.sh 901
  if has_call "setup-worktree" && [ "$(readlink -f "$WT/data/shared")" = "$(readlink -f "$SANDBOX/repo/data/shared")" ]; then
    ok "★ $bad を指す symlink を共有ストアへ張り直した（偽の ok を出さない。#527）"
  else ng "$bad を指す symlink のまま「共有ストアへの symlink」と扱った（#527 の再発）"; fi
done
# ★ data/ 自体がメインリポジトリへの symlink（worktrees/issue92 の形）→ ストアに解決するので**呼ばない**（毎回張り直す誤りの検査）
rm -rf "$WT/data"; ln -s ../../data "$WT/data"; rm -f "$SANDBOX/calls.log"
flow 0 "data/ がメインリポジトリへの symlink でも 0" issue-start.sh 901
if has_call "setup-worktree"; then ng "data/ 経由でストアに解決するのに setup-worktree.sh を呼んだ（#527）"
else ok "★ data/ 経由でストアに解決するなら setup-worktree.sh を呼ばない（#527）"; fi
rm -f "$WT/data"
# ★ ストア自体が symlink（#215 の形）→ 解決後の比較で素通りさせず止まる
mv "$SANDBOX/repo/data/shared" "$SANDBOX/store-real"; ln -s "$SANDBOX/store-real" "$SANDBOX/repo/data/shared"
flow 1 "★ 共有ストア自体が symlink なら止まる（#215 の形を ok と出さない。#527）" issue-start.sh 901
rm -f "$SANDBOX/repo/data/shared"; mv "$SANDBOX/store-real" "$SANDBOX/repo/data/shared"

# ★ 種類ラベルごとの接頭辞（間違えても check_branch は BRANCH_TYPES に含むので落ちない）
setup_sandbox
i=930
for pair in feature:feature chore:chore spec:spec bug:fix survey:survey experiment:experiment validation:validation docs:docs refactor:refactor; do
  kind="${pair%%:*}"; want="${pair##*:}"
  fixture "940:task:OPEN:t:parent=800
$i:$kind:OPEN:x:parent=940
"
  ( cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" bash scripts/flow/issue-start.sh "$i" ) >/dev/null 2>&1
  got="$(git -C "$SANDBOX/repo/worktrees/task940" branch --show-current 2>/dev/null || true)"
  if [ "$got" = "$want/940-i$i" ]; then ok "接頭辞: $kind → $want/"
  else ng "接頭辞: $kind は $want/940-i$i になるはず（実際 '$got'）"; fi
  (cd "$SANDBOX/repo" && bash scripts/worktree-relative.sh remove worktrees/task940 --force) >/dev/null 2>&1
  git -C "$SANDBOX/repo" branch -D "$want/940-i$i" >/dev/null 2>&1
  i=$((i + 1))
done

# ★ 本物の configure-agent-workflow.sh を新しい worktree に当てても作業ツリーが clean のまま
#   （汚れると commit.sh merge が必ず止まり、quick.sh が生成物をコミットする）
R="$SANDBOX/realcfg"; rm -rf "$R"; mkdir -p "$R"
( cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z | xargs -0 tar cf - ) | tar xf - -C "$R"
( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t \
  && git add -A && git commit -qm x && git worktree add -q --detach "$R/worktrees/w1" ) >/dev/null 2>&1
out="$(bash "$R/scripts/configure-agent-workflow.sh" "$R/worktrees/w1" 2>&1)"; rc=$?
dirty="$(git -C "$R/worktrees/w1" status --porcelain 2>&1)"
if [ "$rc" -eq 0 ] && [ -z "$dirty" ]; then ok "★ 本物の configure-agent-workflow.sh の後も新しい worktree は clean"
else ng "configure-agent-workflow.sh で worktree が汚れた（rc=$rc）: $dirty $(printf '%s' "$out" | tail -2)"; fi
bash "$R/scripts/configure-agent-workflow.sh" "$R" >/dev/null 2>&1 || true
if [ -f "$R/.claude/settings.json" ]; then ok "main のチェックアウトではフックを登録する（.claude/settings.json を作る）"
else ng "main のチェックアウトでもフックを登録しなくなった"; fi
rm -rf "$R"

# ★ <TASK> の解決（親 task / 親なし / 親 epic）
setup_sandbox
flow 0 "親が task → ブランチ番号は task の番号" issue-start.sh 901
if [ -d "$SANDBOX/repo/worktrees/task900" ]; then ok "worktrees/task900 になる"
else ng "worktrees/task900 が無い"; fi
setup_sandbox
flow 0 "親なし（単発 bug）→ ブランチ番号は自分の番号" issue-start.sh 910
if [ -d "$SANDBOX/repo/worktrees/issue910" ]; then ok "worktrees/issue910 になる（task 単位でない）"
else ng "worktrees/issue910 が無い"; fi
got="$(git -C "$SANDBOX/repo/worktrees/issue910" branch --show-current 2>/dev/null || true)"
if [ "$got" = "fix/910-bug" ]; then ok "ブランチは <prefix>/<N>-<slug>（日本語の題名は種類名で埋める: $got）"
else ng "親なしのブランチ名が fix/910-bug でない（実際 '$got'）"; fi
if has_call "configure-agent-workflow $SANDBOX/repo/worktrees/issue910"; then
  ok "★ worktree を作った直後に configure-agent-workflow.sh <worktree> を呼ぶ"
else ng "configure-agent-workflow.sh を呼んでいない（worktree でスキルが見つからない）"; fi
rm -f "$SANDBOX/calls.log"
flow 0 "（再実行）既に worktree がある" issue-start.sh 910
if has_call "configure-agent-workflow"; then ng "作っていないのに configure-agent-workflow.sh を呼んだ"
else ok "作らなかったときは configure-agent-workflow.sh を呼ばない"; fi
setup_sandbox
fixture "${DEFAULT_FIXTURE}912:bug:OPEN:Fix CRLF parsing!:parent=
"
flow 0 "親なし・英語の題名" issue-start.sh 912
got="$(git -C "$SANDBOX/repo/worktrees/issue912" branch --show-current 2>/dev/null || true)"
if [ "$got" = "fix/912-fix-crlf-parsing" ]; then ok "slug は題名の英数字（$got）"
else ng "英語の題名の slug が fix/912-fix-crlf-parsing でない（実際 '$got'）"; fi
setup_sandbox
fixture "940:task:OPEN:t:parent=800
960:question:OPEN:未知の種類:parent=940
"
flow 1 "★ 表に無い種類ラベル → 止まる（既定の接頭辞に丸めない）" issue-start.sh 960
setup_sandbox
fixture "800:epic:OPEN:親epic:parent=
950:feature:OPEN:epic 直下:parent=800
"
flow 0 "親が epic → ブランチ番号は自分の番号" issue-start.sh 950
if [ -d "$SANDBOX/repo/worktrees/issue950" ]; then ok "worktrees/issue950 になる"
else ng "worktrees/issue950 が無い"; fi
# ★ worktree の登録だけ残っている / 別 slug のブランチが残っている
setup_sandbox
flow 0 "（前提）worktree を作る" issue-start.sh 901
rm -rf "$SANDBOX/repo/worktrees/task900"
flow 1 "登録だけ残って実体が無い → 落ちる" issue-start.sh 901
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'worktree-relative.sh remove' || true)" -gt 0 ]; then ok "出力が scripts/worktree-relative.sh remove を促す（lock された登録も消せる）"
else ng "worktree-relative.sh remove の案内が無い"; fi
(cd "$SANDBOX/repo" && bash scripts/worktree-relative.sh remove worktrees/task900 --force) >/dev/null 2>&1
# ★ **別番号**のブランチで worktree が既存 → 勝手に消さずに落ちる
git -C "$SANDBOX/repo" worktree add "$SANDBOX/repo/worktrees/task900" -b "feature/777-x" >/dev/null 2>&1
flow 1 "worktrees/task900 が別番号のブランチ（feature/777-x）で存在する → 非ゼロ" issue-start.sh 901
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'worktree-safe-remove' || true)" -gt 0 ]; then
  ok "勝手に消さず /worktree-safe-remove を促す"
else ng "/worktree-safe-remove の案内が無い"; fi
git -C "$SANDBOX/repo" worktree remove --force "$SANDBOX/repo/worktrees/task900" 2>/dev/null
git -C "$SANDBOX/repo" branch -D "feature/777-x" >/dev/null 2>&1

git -C "$SANDBOX/repo" branch -m "spec/900-i901" "spec/900-other" 2>/dev/null
rm -f "$SANDBOX/gh-body.log"
flow 0 "同じ task の**別 slug**のブランチが残っている → それを使う（2 本目を作らない）" issue-start.sh 901
if [ "$(git -C "$SANDBOX/repo/worktrees/task900" branch --show-current)" = "spec/900-other" ]; then ok "既存ブランチ spec/900-other を再利用した"
else ng "新しいブランチを作ってしまった（1 task = 1 ブランチに反する）"; fi
# ★ #527: 着手コメントには**実際に使った**ブランチ名を書く（使わなかった新規名 spec/900-i901 を書かない）
if [ "$(grep -cF 'spec/900-other' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -gt 0 ] \
   && [ "$(grep -cF 'spec/900-i901' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -eq 0 ]; then
  ok "★ 着手コメントに再利用したブランチ名 spec/900-other が出る（#527）"
else ng "着手コメントに使われなかったブランチ名が出ている（#527 の再発）"; fi
# ══════════════════════════════════════════════════════════════════
# §7-5 issue-branch.sh
# ══════════════════════════════════════════════════════════════════
echo "--- §7-5 issue-branch.sh ---"
setup_sandbox
flow 1 "main に居ると落ちる"            issue-branch.sh --title t
# ★ **落ちた理由まで見る**（#554）。ブランチ名の形の検査でも 1 で落ちるので、
#   終了コードだけでは「保護ブランチの判定が効いている」ことを示せない（実際に素通りしていた）
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'issue のブランチで実行すること' || true)" -gt 0 ]; then
  ok "★ 落ちた理由が保護ブランチの判定である（形の検査に素通りしていない）"
else ng "保護ブランチの判定を素通りしている: $(printf '%s' "$LAST_OUT" | tail -2)"; fi
flow 1 "--title が無いと落ちる"         issue-branch.sh --type feature
flow 1 "未知のオプションで落ちる"       issue-branch.sh --title t --lable x

flow 0 "（前提）worktree を作る" issue-start.sh 901
WT="$SANDBOX/repo/worktrees/task900"
# ★ ブランチ名に番号が無い形（issue-branch.sh:32-33 の die）
git -C "$WT" checkout -q -b "feature/no-number" 2>/dev/null
flow_in "$WT" 1 "ブランチ名に番号が無いと落ちる（<type>/<番号>- の形でない）" \
  issue-branch.sh --title t
git -C "$WT" checkout -q "spec/900-i901"
before="$(git -C "$WT" branch --show-current)"
flow_in "$WT" 0 "worktree の中で小タスクを作れる" issue-branch.sh --title "小タスク"
after="$(git -C "$WT" branch --show-current)"
if [ "$before" = "$after" ]; then ok "実行前後でブランチが変わらない（切り替えない）"
else ng "ブランチが $before → $after に変わった"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '親 #900' || true)" -gt 0 ]; then ok "親は 900（spec/900-i901 の i901 を拾わない）"
else ng "親番号の抽出がおかしい"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '#4242' || true)" -gt 0 ]; then ok "issue-create.sh の stdout（作成: #4242）を解析して子番号にする"
else ng "子番号を受け取れていない"; fi
if [ "$(grep -cF 'comment 4242' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then ok "子 #4242 にも着手コメントを付ける"
else ng "子へのコメントが無い"; fi
if [ "$(grep -cF 'comment 900' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then ok "親 #900 にも報告する"
else ng "親へのコメントが無い"; fi
# ★ gh issue create に渡った引数を見る（偽 gh が記録する）。#118 の実害面はここ
if [ "$(grep -cF -- '--label feature' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then
  ok "--type 省略時に feature が --label として渡る"
else ng "既定の --type が feature になっていない（または --label を渡していない）"; fi
if [ "$(grep -cF -- '--assignee @me' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then
  ok "--assignee @me が渡る" ; else ng "assignee を渡していない"; fi
# 日本語・引用符（eval を使っていないこと）
flow_in "$WT" 0 'title に日本語と " が入っても通る' issue-branch.sh --title 'a"b 日本語'

# ══════════════════════════════════════════════════════════════════
# §7-5b realign_branch（#565。squash merge の後、枝を既定ブランチに合わせ直す）
#   ★ gh は要らない。**本物の git だけ**で、衝突が起きる状況を作って確かめる
# ══════════════════════════════════════════════════════════════════
echo "--- §7-5b realign_branch（#565）---"

# rb_setup → $SANDBOX/rb に「1 回 squash merge した後」の状態を作る
rb_setup() {
  local R="$SANDBOX/rb"
  rm -rf "$R" "$SANDBOX/rb-remote.git"
  git init -q --bare "$SANDBOX/rb-remote.git"
  mkdir -p "$R"
  ( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t \
    && echo base > a.txt && git add -A && git commit -qm base \
    && git remote add origin "$SANDBOX/rb-remote.git" && git push -q origin main \
    && git checkout -q -b "spec/900-i901" \
    && echo child1 > c1.txt && git add -A && git commit -qm "子 1

Refs #901" \
    && git push -q origin "spec/900-i901" \
    && git checkout -q main \
    && git merge -q --squash "spec/900-i901" && git commit -qm "squash 済み" \
    && git push -q origin main \
    && git checkout -q "spec/900-i901" ) >/dev/null 2>&1
}

# ★ **前提**: 合わせ直す前は、2 回目の squash merge が衝突する
#   ★ 衝突の正体は **add/add**（実測）。1 回目の子が**足した**ファイルを 2 回目の子が書き換えると、
#     main 側の squash コミットも同じパスを「足した」ことになり、共通祖先から見て両側が add になる。
#     **1 回目の内容に触らない場合は衝突しない**ので、再現にはこの形が要る
rb_setup
( cd "$SANDBOX/rb" && echo "child1 を書き換える" >> c1.txt && git add -A && git commit -qm "子 2

Refs #902" ) >/dev/null 2>&1
if ( cd "$SANDBOX/rb" && git checkout -q main && git merge --squash "spec/900-i901" ) >/dev/null 2>&1; then
  ng "（前提）合わせ直す前でも 2 回目の squash が通ってしまう（#565 が再現しない）"
else ok "★（前提）合わせ直さないと 2 回目の squash merge が衝突する（#565 の再現）"; fi

# ★ 合わせ直すと衝突しない
rb_setup
out="$(cd "$SANDBOX/rb" && bash -c '. "$1/lib.sh"; realign_branch "$2" "$3"' _ \
        "$FLOW" "$SANDBOX/rb" "spec/900-i901" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "realign_branch が 0 で終わる"
else ng "realign_branch が $rc で終わった: $(printf '%s' "$out" | tail -2)"; fi
if [ "$(git -C "$SANDBOX/rb" rev-parse HEAD)" = "$(git -C "$SANDBOX/rb" rev-parse origin/main)" ]; then
  ok "★ 枝が origin/main と同じコミットを指す（履歴が揃った）"
else ng "枝が origin/main に揃っていない"; fi
if [ "$(git -C "$SANDBOX/rb" rev-parse "origin/spec/900-i901")" = "$(git -C "$SANDBOX/rb" rev-parse origin/main)" ]; then
  ok "★ origin 側の枝も更新されている（force-with-lease が効いた）"
else ng "origin 側の枝が古いまま（次の子で衝突する）"; fi
if [ -f "$SANDBOX/rb/c1.txt" ]; then ok "★ 1 回目の子の内容は残っている（reset で失っていない）"
else ng "1 回目の子の内容が消えた"; fi
( cd "$SANDBOX/rb" && echo "child1 を書き換える" >> c1.txt && git add -A && git commit -qm "子 2

Refs #902" ) >/dev/null 2>&1
if ( cd "$SANDBOX/rb" && git checkout -q main && git merge --squash "spec/900-i901" ) >/dev/null 2>&1; then
  ok "★ 合わせ直した後は 2 回目の squash merge が通る（#565 が直っている）"
else ng "合わせ直しても 2 回目の squash merge が衝突する"; fi

# ★ 汚れていたら触らない（reset --hard で未コミットの変更を消さない）
rb_setup
( cd "$SANDBOX/rb" && echo dirty > dirty.txt ) >/dev/null 2>&1
before="$(git -C "$SANDBOX/rb" rev-parse HEAD)"
out="$(cd "$SANDBOX/rb" && bash -c '. "$1/lib.sh"; realign_branch "$2" "$3"' _ \
        "$FLOW" "$SANDBOX/rb" "spec/900-i901" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c '汚れている' || true)" -gt 0 ]; then
  ok "★ worktree が汚れていたら触らない（理由も出す）"
else ng "汚れているのに触った（rc=$rc）"; fi
if [ "$(git -C "$SANDBOX/rb" rev-parse HEAD)" = "$before" ] && [ -f "$SANDBOX/rb/dirty.txt" ]; then
  ok "→ 枝も未コミットの変更もそのまま"
else ng "触ってしまった（変更が消えた可能性）"; fi

# ★ 内容が違うなら触らない（まだマージしていない変更がある）
rb_setup
( cd "$SANDBOX/rb" && echo notmerged > n.txt && git add -A && git commit -qm "未マージ

Refs #902" ) >/dev/null 2>&1
before="$(git -C "$SANDBOX/rb" rev-parse HEAD)"
out="$(cd "$SANDBOX/rb" && bash -c '. "$1/lib.sh"; realign_branch "$2" "$3"' _ \
        "$FLOW" "$SANDBOX/rb" "spec/900-i901" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c '違う内容が残っている' || true)" -gt 0 ]; then
  ok "★ origin/main と違う内容が残っていたら触らない（マージしていない変更を消さない）"
else ng "未マージの変更があるのに触った（rc=$rc）"; fi
if [ "$(git -C "$SANDBOX/rb" rev-parse HEAD)" = "$before" ]; then ok "→ 枝はそのまま"
else ng "枝を動かしてしまった"; fi

# ══════════════════════════════════════════════════════════════════
# §7-6 issue-finish.sh
# ══════════════════════════════════════════════════════════════════
echo "--- §7-6 issue-finish.sh ---"
# ── #668 V2 の判定（LAST_OUT を見る）──────────────────────────────
n_out() { printf '%s' "$LAST_OUT" | grep -cE -e "$1" || true; }
assert_task_next() {  # 親 task があるとき: task-run.sh 900 の案内が残り、引き継ぎは出さない
  if [ "$(n_out 'task-run\.sh 900([^0-9]|$)')" -gt 0 ]; then ok "$1: task-run.sh 900 の案内が残る"
  else ng "$1: task-run.sh 900 の案内が無い"; fi
  if [ "$(n_out 'handoff\.sh write|/compact')" -eq 0 ]; then ok "$1: 引き継ぎ手順を出さない（task の最後に 1 回だけ）"
  else ng "$1: 親 task があるのに引き継ぎ手順を出している"; fi
}
assert_handoff() {  # assert_handoff <説明> <書き先> [<書いてはいけない番号>]
  if [ "$(n_out "handoff\.sh write $2 -([[:space:]]|\$)")" -gt 0 ] && [ "$(n_out '/compact')" -gt 0 ] \
     && [ "$(n_out 'ワーカーは行わない')" -gt 0 ]; then ok "$1: handoff.sh write $2 と /compact を案内する"
  else ng "$1: 引き継ぎ手順（write $2・/compact・ワーカーは行わない）が揃っていない"; fi
  if [ -n "${3:-}" ] && [ "$(n_out "handoff\.sh write $3([^0-9]|\$)")" -gt 0 ]; then
    ng "$1: 書き先を #$3 にしている（\$N と \$TASK の取り違え）"; fi
  if [ "$(n_out 'task-run\.sh|/clear|もう一度このスクリプトを')" -eq 0 ]; then
    ok "$1: task-run.sh の誤案内・/clear・再呼び出しを出さない"
  else ng "$1: task-run.sh・/clear・再呼び出しのいずれかを出している"; fi
}
prepare_finish() {  # 揃った状態を作る（worktree・コミット・PR）
  setup_sandbox
  ( cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" bash scripts/flow/issue-start.sh 901 ) >/dev/null 2>&1
  WT="$SANDBOX/repo/worktrees/task900"
  mkdir -p "$WT/.spec/issues"   # ★ 空ディレクトリは git が追跡しないので worktree には無い
  printf '# Issue #901: x\n\n- ステータス: completed\n' > "$WT/.spec/issues/901-x.md"
  ( cd "$WT" && git add -A && git commit -qm "spec: x

Refs #901" ) >/dev/null
  export GH_PR_HEAD="spec/900-i901"
  rm -f "$SANDBOX/calls.log"
}
fin() {  # fin <期待コード> <説明> [環境...]
  local want="$1" what="$2"; shift 2
  flow_in "$WT" "$want" "$what" issue-finish.sh 901 900
}

prepare_finish
fin 0 "全部揃っていれば 0 で終わる"
assert_task_next "親 task あり（通常経路）"
if has_call "merge args=merge 901 900"; then ok "\$MERGE_CMD を merge サブコマンドで呼ぶ"
else ng "\$MERGE_CMD を呼んでいない"; fi
# ★ §6-5 の動的オラクル: $MERGE_CMD は **worktree に居たまま**呼ばれる
#   （静的な行番号比較だけだと、cd "$(main_repo)" のように綴りを変えた実装が素通りする）
if [ "$(calls | grep -cF "merge cwd=$WT" || true)" -gt 0 ]; then
  ok "★ \$MERGE_CMD は worktree の中から呼ばれた（先に cd する実装に戻すと落ちる）"
else ng "\$MERGE_CMD がメインリポジトリから呼ばれている（check merge が必ず落ちる）"; fi
if has_call "quality scope=docs"; then ok "品質チェックを呼ぶ（spec 段なので scope=docs）"
else ng "品質チェックを呼んでいない"; fi
if [ "$(grep -cF 'close 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then ok "#901 を close する"
else ng "close していない"; fi
# 他に open な子（902）が居るので worktree パスは渡さない
if [ "$(calls | grep -cE 'merge args=merge 901 900$' || true)" -gt 0 ]; then ok "open な子が残っている → 第 2 引数を渡さない"
else ng "worktree パスを渡してしまった（次の段が続けられなくなる）"; fi
# ★ 枝を残すなら、段 9b（#565）を通る。通らないと次の子の squash merge が add/add で衝突する
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '枝を既定ブランチに合わせ直す' || true)" -gt 0 ]; then
  ok "★ 枝を残すときは段 9b（枝の合わせ直し）を通る（#565）"
else ng "段 9b を通っていない（次の子で squash merge が衝突する）"; fi
# ★ 最後の子なら worktree パスを**渡す**（#N 自身は数に入れない）
prepare_finish
fixture "${DEFAULT_FIXTURE//902:feature:OPEN/902:feature:CLOSED}"
fin 0 "最後の子（#901 自身は open のまま）→ 0 で終わる"
if [ "$(calls | grep -cF "merge args=merge 901 900 $WT" || true)" -gt 0 ]; then ok "第 2 引数が worktree のパスと一致（値で見る。#N を除いて数えている）"
else ng "worktree パスが渡っていない（#N 自身で塞がる恒偽）"; fi
# ★ 枝を消すなら段 9b は通らない（消すものを合わせ直しても意味が無い。恒真でないことの確認）
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '枝を既定ブランチに合わせ直す' || true)" -eq 0 ]; then
  ok "★ 枝を消すときは段 9b を通らない（段 9b が無条件ではない）"
else ng "枝を消すのに合わせ直そうとしている"; fi
# ★ 本物と同じく worktree を消す偽物でも、close まで到達する（CWD 消失で exit 128 にしない）
prepare_finish
fixture "${DEFAULT_FIXTURE//902:feature:OPEN/902:feature:CLOSED}"
: > "$SANDBOX/merge_removes_wt"
fin 0 "worktree を消す偽 commit.sh でも close まで到達する"
if [ "$(grep -cF 'close 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then ok "worktree 削除後も close できる（cd を先に済ませている）"
else ng "close に到達していない"; fi
rm -f "$SANDBOX/merge_removes_wt"

# ★ 落ちる側（いずれも $MERGE_CMD を呼ばない）
prepare_finish; echo 1 > "$SANDBOX/quality_rc"
fin 1 "品質チェックが落ちると非ゼロ"
if has_call "merge args"; then ng "品質チェック失敗でもマージしている"
else ok "→ \$MERGE_CMD を呼ばない"; fi
prepare_finish; printf '# Issue #901: x\n\n- ステータス: draft\n' > "$WT/.spec/issues/901-x.md"
( cd "$WT" && git add -A && git commit -qm "draft

Refs #901" ) >/dev/null
fin 1 "仕様ファイルが draft のままだと非ゼロ"
if has_call "merge args"; then ng "draft でもマージしている"
else ok "→ \$MERGE_CMD を呼ばない"; fi
prepare_finish
mkdir -p "$WT/.dev/qa"
printf '{"id":"Q001","issue":901,"timestamp":"2026-09-18T00:00:00Z","question":"x","type":"provisional"}\n' > "$WT/.dev/qa/questions.jsonl"
fin 1 "未回答の QA があると非ゼロ"
if has_call "merge args"; then ng "未回答 QA でもマージしている"
else ok "→ \$MERGE_CMD を呼ばない"; fi
printf '{"id":"Q001","timestamp":"2026-09-18T00:00:00Z","answer":"y","by":"t"}\n' > "$WT/.dev/qa/answers.jsonl"
fin 0 "全件回答済みなら落ちない（★ [ -s questions.jsonl ] で落とす実装を捕まえる）"

prepare_finish
if [ ! -d "$WT/.dev/qa" ]; then ok "（前提）QA の置き場所は無い"
else ng "QA の置き場所が残っている"; fi
fin 0 "QA の置き場所が無くても落ちない（恒偽でない）"

prepare_finish; rm -f "$WT/.spec/issues/901-x.md"
printf 'Issue #901\n停止条件: 該当なし\n' > "$WT/.spec/issues/901-auto-decisions.md"
( cd "$WT" && git add -A && git commit -qm "auto-decisions only

Refs #901" ) >/dev/null
fin 0 "auto-decisions しか無い場合は落ちない（*-auto-decisions* を除外している）"

prepare_finish
GH_PR_NO_REVIEW=1 flow_in "$WT" 1 "PR 本文に /review 結果が無いと非ゼロ" issue-finish.sh 901 900
if has_call "merge args"; then ng "レビュー結果なしでマージしている"
else ok "→ \$MERGE_CMD を呼ばない"; fi
prepare_finish
GH_PR_HEAD="other" flow_in "$WT" 1 "PR が無いと非ゼロ（push と gh pr create を促す）" issue-finish.sh 901 900
if has_call "merge args"; then ng "PR が無いのにマージしている"
else ok "→ \$MERGE_CMD を呼ばない"; fi
prepare_finish
GH_PR="77 78" flow_in "$WT" 1 "同じ head に open な PR が 2 本 → 非ゼロ（.[0] で選ばない）" issue-finish.sh 901 900

# ★ 還流候補（空出力の実装を落とす）
prepare_finish; : > "$SANDBOX/reflux"
fin 0 "還流候補がある差分でも 0 で終わる"
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '還流候補' || true)" -gt 0 ]; then ok "還流候補を出力する（空のままの実装を落とす）"
else ng "還流候補が出力されていない"; fi
rm -f "$SANDBOX/reflux"

# ★ Refs #N を持つコミットが無い
prepare_finish
( cd "$WT" && git commit -q --amend -m "参照なしのコミット" ) >/dev/null
fin 1 "Refs #N を持つコミットが無いと非ゼロ"
if has_call "merge args"; then ng "Refs が無いのにマージしている"; else ok "→ \$MERGE_CMD を呼ばない"; fi
# ★ 検査は品質チェックより先（#554）。**動的に見る**（行番号で見ると、挙動を変えない
#   書き換え（`if ! check merge …; then`）で落ちる恒偽になる）。
#   いま落ちたのは check merge だけなので、先なら品質チェックは一度も呼ばれていない
if has_call "quality scope="; then
  ng "check merge が落ちる前に品質チェックを走らせている（commit.sh と順序が逆）"
else ok "★ issue-finish.sh も check merge → 品質チェックの順"; fi

# ★ ステータス行が無い仕様ファイル（番号による免除は無い）
prepare_finish
printf '# Issue #901: x\n\n（メタ情報にステータス行が無い）\n' > "$WT/.spec/issues/901-x.md"
( cd "$WT" && git add -A && git commit -qm "no status

Refs #901" ) >/dev/null
fin 1 "ステータス行が無い → 非ゼロ"
if [ "$(grep -c 'LEGACY_MAX' "$WT/scripts/check-discipline.sh" "$WT/scripts/flow/issue-finish.sh" | awk -F: '{s+=$2} END {print s}')" -eq 0 ]; then
  ok "番号による免除（LEGACY_MAX）が無い"; else ng "LEGACY_MAX が残っている"; fi

# ★ マージ済み・#N は open・**worktree は残っている**（MERGED_DONE の経路）
prepare_finish
rm -f "$SANDBOX/calls.log"
out="$(cd "$WT" && PATH="$SANDBOX/bin:$PATH" GH_PR_STATE=merged GH_PR_HEAD="spec/900-i901" \
       bash "$WT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "マージ済み（open な PR は無い）→ 0 で終わる"
else ng "MERGED_DONE の経路が 0 にならない（rc=$rc）"; fi
if has_call "merge args"; then ng "マージ済みなのに \$MERGE_CMD を呼んでいる"
else ok "→ \$MERGE_CMD を呼ばない"; fi
if [ "$(grep -cF '削除した' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -eq 0 ]; then
  ok "完了コメントに「削除した」と書かない（段 9 を飛ばしている）"
else ng "消していないのに「削除した」と記録している"; fi
# ★ #715: 枝を使い回したとき、前の段（#902）の merged な PR を今回の PR と取り違えない
for closes in "Closes #902" "Refs #9010" "discloses #901" ""; do
  prepare_finish
  out="$(cd "$WT" && PATH="$SANDBOX/bin:$PATH" GH_PR_STATE=merged GH_PR_HEAD="spec/900-i901" GH_PR_CLOSES="$closes" \
         bash "$WT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$(grep -cF 'close 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -eq 0 ]; then
    ok "★ merged な PR の本文が '${closes:-（Closes なし）}' → 止まり、#901 を close しない（#715）"
  else ng "merged な PR の本文が '${closes:-（Closes なし）}' なのに #901 を close した（rc=$rc。#715 の再発）"; fi
done
prepare_finish
out="$(cd "$WT" && PATH="$SANDBOX/bin:$PATH" GH_PR_STATE=merged GH_PR_HEAD="spec/900-i901" GH_PR_CLOSES="fixes #901." \
       bash "$WT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "merged な PR の本文が 'fixes #901.'（小文字・句点付き）でも今回の PR とみなす（恒偽でない）"
else ng "'fixes #901.' を今回の PR とみなさない（rc=$rc）"; fi
# ★ merged な PR が 2 本（前の段 77・今回 78）。**並びによらず** #901 を参照する 78 を採る
for order in "77 78" "78 77"; do
  prepare_finish
  out="$(cd "$WT" && PATH="$SANDBOX/bin:$PATH" GH_PR_STATE=merged GH_PR_HEAD="spec/900-i901" GH_PR="$order" \
         GH_PR_CLOSES_77="Refs #902" GH_PR_CLOSES_78="Refs #901" bash "$WT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == *"（PR 78）"* ]]; then ok "★ merged な PR が '$order' の順でも #901 を参照する PR 78 を採る（#715）"
  else ng "merged な PR が '$order' の順のとき PR 78 を採らない（rc=$rc。1 本目だけ見ている）"; fi
done

# ★ QA の計数が壊れている場合は die する（「検査できなかった」を 0 件と読まない）
prepare_finish
mkdir -p "$WT/.dev/qa"
printf '{"id":"Q001","issue":901,"timestamp":"2026-09-18T00:00:00Z","question":"x","type":"provisional"}\n' \
  > "$WT/.dev/qa/questions.jsonl"
mv "$WT/scripts/qa" "$WT/scripts/qa.off"
fin 1 "scripts/qa が無いと非ゼロ（未回答 0 件と読まない）"
mv "$WT/scripts/qa.off" "$WT/scripts/qa"
printf 'print("warning: store initialized")\n' >> "$WT/scripts/qa/store.py"
fin 1 "store.py が数値以外を出したら非ゼロ（integer expression expected の無言終了を防ぐ）"
( cd "$WT" && git checkout -- scripts/qa/store.py ) 2>/dev/null

# ★ exit 10（マージは済んだが後片付けで失敗）の**受け側**（534 §3-4 / R3）
prepare_finish
echo 10 > "$SANDBOX/merge_rc"
fin 0 "★ \$MERGE_CMD が exit 10 なら 0 で終わる（マージは済んでいるので close まで進む）"
if [ "$(grep -cF 'close 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then
  ok "★ exit 10 でも #901 を close する（open のまま残さない）"
else ng "exit 10 で close していない（issue が open のまま残る）"; fi
if [ "$(grep -cF '後片付けのどこかが失敗した' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -gt 0 ]; then
  ok "★ 完了コメントに「後片付けのどこかが失敗した」と書く（「削除した」と嘘をつかない）"
else ng "exit 10 なのに嘘の完了報告をしている"; fi
# ★ **どれが失敗したかを断定しない**（#554 の /review。既定ブランチの更新かもしれない）
if [ "$(grep -cF '既定ブランチの更新' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -gt 0 ]; then
  ok "★ 失敗候補を worktree に限定していない（既定ブランチの更新も挙げる）"
else ng "完了コメントが worktree の失敗と断定している（記録が読み手を誤らせる）"; fi
# ★ worktree の片付け方は scripts/worktree-relative.sh remove（lock を外してから消す）
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'worktree-relative.sh remove' || true)" -gt 0 ]; then
  ok "★ 残った worktree の片付け方に scripts/worktree-relative.sh remove を出す"
else ng "残った worktree の片付け方に worktree-relative.sh remove が無い"; fi
rm -f "$SANDBOX/merge_rc"

# ★ マージそのものが失敗したら非ゼロ
prepare_finish
echo 1 > "$SANDBOX/merge_rc"
fin 1 "\$MERGE_CMD が非ゼロで終わったら非ゼロ（マージ失敗を飲まない）"
if has_call "merge args"; then ok "→ \$MERGE_CMD は呼ばれている（呼ばずに落ちたのではない）"
else ng "\$MERGE_CMD を呼んでいない"; fi
rm -f "$SANDBOX/merge_rc"

# ★ 再入（main で実行。worktree もブランチも消えた後）
prepare_finish
( cd "$SANDBOX/repo" && git merge --squash --no-commit "spec/900-i901" >/dev/null 2>&1
  git -C "$SANDBOX/repo" commit -qm "merged

Refs #901" && git -C "$SANDBOX/repo" update-ref refs/remotes/origin/main HEAD ) >/dev/null
flow 0 "再入（main で実行・作業は main に入っている）→ 0 で close する" issue-finish.sh 901 900
assert_task_next "親 task あり（再入経路）"
if has_call "merge args"; then ng "再入でマージを呼んでいる"
else ok "→ \$MERGE_CMD を呼ばない"; fi
if [ "$(grep -cF 'close 901' "$SANDBOX/gh.log" 2>/dev/null || true)" -gt 0 ]; then ok "再入でも close まで到達する（手作業を要求しない）"
else ng "close していない"; fi
if [ "$(grep -cF '削除した' "$SANDBOX/gh-body.log" 2>/dev/null || true)" -eq 0 ]; then ok "再入の完了コメントに「削除した」と書かない（実際には消していない）"
else ng "再入なのに worktree を削除したと記録している"; fi
flow 1 "main で実行・作業が main に入っていない → 非ゼロ（issue-start を促す）" issue-finish.sh 902 900

# ══════════════════════════════════════════════════════════════════
# #668 V2: 親 task を持たない issue（910 bug）と、その小タスク（911。親 910 は通常の issue）
#   引数 3 通り × 通常・再入の 2 経路。書き先は $TASK（910）
# ══════════════════════════════════════════════════════════════════
echo "--- #668 親 task なしの完了（引き継ぎ手順）---"
prepare_np() {  # prepare_np <閉じる issue>  worktree は #910 のもの（小タスクは親と共有）
  setup_sandbox
  [ "$1" = 910 ] || fixture "${DEFAULT_FIXTURE}911:bug:OPEN:小タスク:parent=910
"
  ( cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" bash scripts/flow/issue-start.sh 910 ) >/dev/null 2>&1
  WT="$SANDBOX/repo/worktrees/issue910"
  ( cd "$WT" && echo x > fix.txt && git add fix.txt && git commit -qm "fix: x

Refs #$1" ) >/dev/null
  export GH_PR_HEAD="fix/910-bug"
  rm -f "$SANDBOX/calls.log"
}
np_merge_into_main() {  # 再入の前提: 作業が main に入っている
  # ★ squash merge の失敗を握りつぶさない（落ちたら再入経路の検査が無意味になる。#661）
  local log
  if ! log="$(cd "$SANDBOX/repo" && git merge --squash --no-commit "fix/910-bug" 2>&1)"; then
    ng "np_merge_into_main: git merge --squash が失敗した: $log"; return 1
  fi
  if ! log="$(git -C "$SANDBOX/repo" commit -qm "merged

Refs #$1" 2>&1 && git -C "$SANDBOX/repo" update-ref refs/remotes/origin/main HEAD 2>&1)"; then
    ng "np_merge_into_main: commit か update-ref が失敗した: $log"; return 1
  fi
}
for args in "910" "910 910" "911 910"; do
  n="${args%% *}"; bad=""; [ "$n" = 910 ] || bad="$n"
  prepare_np "$n"
  # shellcheck disable=SC2086  # 引数の並びを分割して渡す
  flow_in "$WT" 0 "親 task なし（issue-finish.sh $args・通常経路）→ 0 で終わる" issue-finish.sh $args
  assert_handoff "親 task なし（$args・通常経路）" 910 "$bad"
  prepare_np "$n"; np_merge_into_main "$n" || continue
  # shellcheck disable=SC2086
  flow 0 "親 task なし（issue-finish.sh $args・再入経路）→ 0 で終わる" issue-finish.sh $args
  if [ "$(n_out '再入経路')" -gt 0 ]; then ok "（前提）$args は再入経路を通った"
  else ng "$args: 再入経路を通っていない（fixture が壊れている）"; fi
  assert_handoff "親 task なし（$args・再入経路）" 910 "$bad"
done

# ★ メインリポジトリで task ブランチに居る場合、worktree パスを渡さない
setup_sandbox
( cd "$SANDBOX/repo" && git checkout -q -b "spec/900-i901" && mkdir -p .spec/issues && printf '# Issue #901: x\n\n- ステータス: completed\n' > .spec/issues/901-x.md && git add -A && git commit -qm "x

Refs #901" ) >/dev/null
fixture "${DEFAULT_FIXTURE//902:feature:OPEN/902:feature:CLOSED}"
GH_PR_HEAD="spec/900-i901" flow 0 "メインリポジトリで実行しても 0 で終わる" issue-finish.sh 901 900
if [ "$(calls | grep -cE 'merge args=merge 901 900$' || true)" -gt 0 ]; then ok "メインリポジトリのパスを \$MERGE_CMD に渡さない（main のブランチを消させない）"
else ng "メインリポジトリのパスを渡してしまった"; fi
echo
printf '成立 %d / 不成立 %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
