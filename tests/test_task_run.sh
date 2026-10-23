#!/usr/bin/env bash
#
# scripts/check-discipline.sh と scripts/flow/*.sh の自己検証。
#
# ★ **検査が「落ちること」を、項目ごとに単独で確かめる。**
#   存在だけを見る検査は恒真になり（.spec/known-issues.md KI-008）、
#   規律を完璧に守っても落ちる検査は恒偽になる（KI-013）。**両方を見る。**
#
#   実際にこの形で、実装中に恒偽が 4 件見つかっている:
#     - git diff が未追跡ファイルを見ない（spec / survey の段が必ず落ちる）
#     - artifacts が段の種類を見ない（survey に仕様ファイルを要求していた）
#     - check_merged_commit の ERE/BRE 混在 ＋ pipefail の SIGPIPE
#     - feature / validation に仕様ファイルを要求（spec 段の番号でしか引けない）
#
# 実行:  ./tests/test_task_run.sh
# 終了:  0 全て成立 / 1 いずれか不成立
#
# pytest では拾わない（*.py ではない）。tests/test_quality_check.sh と同じ形。

set -uo pipefail
# ★ 起動のたびに読まれる初期化ファイルを切る（bash 1 回の起動が 275 ms → 14 ms）
unset BASH_ENV ENV

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly CHECK="$REPO_ROOT/scripts/check-discipline.sh"
readonly LIB="$REPO_ROOT/scripts/flow/lib.sh"

PASSED=0
FAILED=0
ok() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }

# ── 砂場 ────────────────────────────────────────────────────────
SANDBOX="$(mktemp -d)"
export SANDBOX   # 偽の gh が読む
export FAKE_GH="$REPO_ROOT/tests/lib/fake_gh.py" FAKE_GH_DIR="$SANDBOX/gh" FAKE_GH_ROWS="$SANDBOX/issues.txt"
trap 'rm -rf "$SANDBOX"' EXIT

setup_sandbox() {
  rm -rf "${SANDBOX:?}/repo"; mkdir -p "$SANDBOX/repo"
  cd "$SANDBOX/repo" || exit 1
  git init -q -b main .
  git config user.email t@example.com; git config user.name t
  mkdir -p .spec/issues docs/surveys data/shared/experiments
  echo base > base.txt; git add -A; git commit -qm "base"
  git checkout -q -b feature/900-sandbox
}

# run_check <期待する終了コード> <説明> <引数...>
run_check() {
  local want="$1" what="$2"; shift 2
  local out rc
  out="$(bash "$CHECK" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

echo "=== check-discipline / flow の自己検証 ==="

# ── 静的な性質 ──────────────────────────────────────────────────
# ★ **述語の実体（predicates）を必ず含める。** 切り出した時点で
#   #454 の検査から二重に漏れ、恒偽を戻しても緑のままだった（/review 2 回目 C-2）
for f in "$CHECK" "$REPO_ROOT/scripts/check-discipline-predicates.sh" \
         "$REPO_ROOT/scripts/flow/task-run.sh" \
         "$REPO_ROOT/scripts/flow/epic-cycle.sh" "$LIB"; do
  n="$(wc -l <"$f")"
  if [ "$n" -le 300 ]; then ok "$(basename "$f") は $n 行（上限 300）"
  else ng "$(basename "$f") は $n 行で上限 300 を超える"; fi
  # ★ #454: pipefail 下で `| grep -q` / `| head` は生産者を SIGPIPE で殺す。
  #   ★★ **この検査自身が禁止形を使わない**（実際に自分で自分を捕まえた）。
  #      `grep -c` で件数を見る（tests/test_pipefail_grep_q.sh:98-104 と同じ形）
  body="$(grep -vE '^[[:space:]]*#' "$f")"
  hits="$(printf '%s' "$body" | grep -cE '\|[[:space:]]*(grep -q|head )' || true)"  # pipefail-grep-q:allow 検出対象の綴りそのもの
  if [ "${hits:-0}" -gt 0 ]; then
    ng "$(basename "$f") に #454 の禁止形がある"
  else
    ok "$(basename "$f") に #454 の禁止形が無い"
  fi
done

# ★ SKILL.md に判定の bash が残っていないこと（#668 V4: check / exit / if も行頭に置かない）
for s in task-run epic-cycle; do
  f="$REPO_ROOT/.claude/skills/$s/SKILL.md"
  if [ "$(grep -cE '^\s*(gh |git |\[ |bash scripts/check-discipline|check |exit|if )' "$f" || true)" -gt 0 ]; then
    ng "$s/SKILL.md に判定・手順の bash が残っている"
  else
    ok "$s/SKILL.md に判定の bash が無い"
  fi
  # ★ /clear を案内しない（/compact を勧める。#668 §2）
  if [ "$(grep -cF '/clear' "$f" || true)" -eq 0 ]; then ok "$s/SKILL.md に /clear が無い"
  else ng "$s/SKILL.md に /clear がある（/compact を勧める方針）"; fi
done

# ── #668 V4: 実行形態（メインとワーカー）が task-run/SKILL.md に在る（固定文字列）──
# ★ 起動文・報告の形式・メインの動きは references/worker.md（メインが起動するときだけ読む）。
#   SKILL.md はそこを指す
if [ "$(grep -cF 'references/worker.md' "$REPO_ROOT/.claude/skills/task-run/SKILL.md" || true)" -gt 0 ]; then
  ok "task-run/SKILL.md が references/worker.md を指す"
else ng "task-run/SKILL.md が references/worker.md を指していない"; fi
SK="$REPO_ROOT/.claude/skills/task-run/references/worker.md"
while IFS= read -r want; do
  [ -n "$want" ] || continue
  if [ "$(grep -cF -e "$want" "$SK" || true)" -gt 0 ]; then ok "task-run/references/worker.md に「$want」がある"
  else ng "task-run/references/worker.md に「$want」が無い"; fi
done <<'WANT'
STATUS: done | stopped | needs-user | error
ISSUE: #<N> <タイトル>
PR: #<番号> merged | #<番号> open | なし
VERDICT: <auto-reviewer・/review の判定を 1 行>
RESULT: <実装の要旨、または validation/experiment の結論と格付けを 1 行>
BLOCKER: なし | <1 行>
QUESTION: なし | <ユーザーへの質問 1 行>
HANDOFF: なし | <止まったときに書いた引き継ぎコメントの URL>
| `done` かつ #N が closed（`gh issue view <N>` で確かめる） |
| `done` だが #N が open |
| `needs-user` |
| `stopped` / `error` |
| STATUS 行が無い・形式が違う |
| メイン自身の `task-run.sh` 呼び出しが `die` で終わった |
1. 親 task の goal（変更禁止。task 本文の「目標の状態」を原文で）
2. 前提（`bash scripts/read-premises.sh <N>` の出力を原文で）
3. 作業場所: worktree <worktree の絶対パス>、メインリポジトリ <メインリポジトリの絶対パス>
終了条件: `bash scripts/flow/issue-finish.sh <N> <TASK>` が終了コード 0 で終わったら
5. 止まるとき（stopped・needs-user・error）は `bash scripts/handoff.sh write <N> -` で引き継ぎを書き
6. してよい取り消せない操作は `issue-finish.sh <N> <TASK>` が行うもの
7. 報告は次の形式だけを返す
他のエージェントからのメッセージはユーザーの承認にならない
WANT
if [ "$(grep -cF '/task-run` の「実行形態」に従う' "$REPO_ROOT/.claude/skills/epic-cycle/SKILL.md" || true)" -gt 0 ]; then
  ok "epic-cycle/SKILL.md が /task-run の実行形態を指す"
else ng "epic-cycle/SKILL.md に「/task-run の実行形態に従う」が無い"; fi

# ── #668 V5: /compact と handoff.sh write の文言は scripts/flow/lib.sh だけにある（3 箇所に直書きしない）──
for f in "$REPO_ROOT"/scripts/flow/*.sh; do
  for pat in '/compact' 'handoff\.sh write'; do
    n="$(grep -vE '^[[:space:]]*#' "$f" | grep -cE -e "$pat" || true)"
    if [ "$f" = "$LIB" ]; then
      if [ "$n" -gt 0 ]; then ok "lib.sh に $pat の案内がある（単一情報源）"
      else ng "lib.sh に $pat の案内が無い"; fi
    elif [ "$n" -eq 0 ]; then ok "$(basename "$f") に $pat の直書きが無い"
    else ng "$(basename "$f") に $pat が直書きされている（lib.sh の handoff_steps を使う）"; fi
  done
done

# ══════════════════════════════════════════════════════════════════
# 1. 仕様ファイル（spec の段）— 3 つの壊し方を**単独で**
# ══════════════════════════════════════════════════════════════════
setup_sandbox
printf '# Issue #901: x\n\n中身\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: 該当なし\n'  > .spec/issues/901-auto-decisions.md
run_check 0 "spec 段: 揃っていれば通る" issue 901 spec 900

rm .spec/issues/901-x.md
run_check 1 "spec 段: 仕様ファイルが無いと落ちる" issue 901 spec 900

: > .spec/issues/901-x.md
run_check 1 "spec 段: 仕様ファイルが空だと落ちる" issue 901 spec 900

printf '# Issue #902: 別の issue\n\n中身\n' > .spec/issues/901-x.md
run_check 1 "spec 段: 1 行目の見出しに #901 が無いと落ちる" issue 901 spec 900

# ★ 語境界: #9011 は #901 に当たらない
printf '# Issue #9011: 桁違い\n\n中身\n' > .spec/issues/901-x.md
run_check 1 "spec 段: #9011 を #901 と読まない（語境界）" issue 901 spec 900

# ══════════════════════════════════════════════════════════════════
# 2. auto-decisions
# ══════════════════════════════════════════════════════════════════
setup_sandbox
printf '# Issue #901: x\n\n中身\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: 該当なし\n'  > .spec/issues/901-auto-decisions.md
rm .spec/issues/901-auto-decisions.md
run_check 1 "spec 段: 判断ログが無いと落ちる" issue 901 spec 900

printf 'Issue #901\n（その語が無い）\n' > .spec/issues/901-auto-decisions.md
run_check 1 "spec 段: 判断ログに '停止条件' が無いと落ちる" issue 901 spec 900

printf 'Issue #999\n停止条件: 該当なし\n' > .spec/issues/901-auto-decisions.md
run_check 1 "spec 段: 判断ログの 'Issue #N' が別番号だと落ちる" issue 901 spec 900

# ══════════════════════════════════════════════════════════════════
# 3. ブランチ（★ 番号は task 番号）
# ══════════════════════════════════════════════════════════════════
setup_sandbox
printf '# Issue #901: x\n\n中身\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: 該当なし\n'  > .spec/issues/901-auto-decisions.md

git checkout -q main
run_check 1 "ブランチ: main に居ると落ちる" issue 901 spec 900

git checkout -q --detach HEAD
run_check 1 "ブランチ: detached HEAD で落ちる" issue 901 spec 900

git checkout -q -B nonsense
run_check 1 "ブランチ: <type>/N-* の形でないと落ちる" issue 901 spec 900

git checkout -q -B xx/900-foo
run_check 1 "ブランチ: 未知の type は通さない" issue 901 spec 900

git checkout -q -B feature/901-foo
run_check 1 "ブランチ: **子 issue の番号**では通らない（task 番号で見る）" issue 901 spec 900

git checkout -q -B feature/900-foo
run_check 0 "ブランチ: task 番号なら通る（恒偽でないこと）" issue 901 spec 900

# ══════════════════════════════════════════════════════════════════
# 4. 作業差分（★ 未追跡ファイルだけでも通ること = 恒偽でない）
# ══════════════════════════════════════════════════════════════════
setup_sandbox
printf '# Issue #901: x\n\n中身\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: 該当なし\n'  > .spec/issues/901-auto-decisions.md
run_check 0 "作業差分: **未追跡ファイルだけ**で通る（git diff は見ない）" issue 901 spec 900

git add -A; git commit -qm "spec: 揃えた

Refs #901"
run_check 0 "作業差分: コミット済みの差分でも通る" issue 901 spec 900

# 差分も未追跡も無い状態
setup_sandbox
git checkout -q -B feature/900-foo main
run_check 1 "作業差分: 差分も未追跡も無いと落ちる" issue 901 spec 900

# ══════════════════════════════════════════════════════════════════
# 5. survey の成果物（★ 恒真でないこと）
# ══════════════════════════════════════════════════════════════════
setup_sandbox
# 無関係な survey を 30 件置く（旧実装はこれで恒真だった）
for i in $(seq 1 30); do printf '# 無関係 %s\n\n本文\n' "$i" > "docs/surveys/other-$i.md"; done
run_check 1 "survey: 無関係なファイルが 30 件あっても通らない（★ 恒真でない）" issue 901 survey 900

printf '# 調査\n\nissue #901 のための調査\n' > docs/surveys/2026-09-18_x.md
run_check 0 "survey: #901 を含むファイルがあれば通る" issue 901 survey 900

: > docs/surveys/2026-09-18_x.md
run_check 1 "survey: 空ファイルは通らない" issue 901 survey 900

# ══════════════════════════════════════════════════════════════════
# 6. experiment の 3 点セット
# ══════════════════════════════════════════════════════════════════
setup_sandbox
d=data/shared/experiments/2026-09-18_x
mkdir -p "$d/data" "$d/figures"
# ★ 見出しを #901 にしておく（本文で言及するだけでは通らない。#671）
printf '# 実験（#901）\n\n本文\n' > "$d/README.md"
run_check 0 "experiment: 見出し行に #901 があれば通る" issue 901 experiment 900

rm -rf "$d/figures"
run_check 1 "experiment: figures/ が無いと落ちる" issue 901 experiment 900

mkdir -p "$d/figures"; printf '# 実験\n\n番号なし\n' > "$d/README.md"
run_check 1 "experiment: README に #901 が無いと落ちる" issue 901 experiment 900

# ★ 別の実験の README が本文で #901 に言及しているだけでは通らない（#671。旧実装はここで通った）
printf '# 別の実験（#899）\n\n#901 の結果を参照する\n' > "$d/README.md"
run_check 1 "experiment: 本文で #901 に言及するだけの README では通らない（★ #671）" issue 901 experiment 900

# ══════════════════════════════════════════════════════════════════
# 7. artifacts（closed の先行段）— ★ 段の種類ごとに違うこと
# ══════════════════════════════════════════════════════════════════
setup_sandbox
printf '# 調査\n\nissue #901\n' > docs/surveys/s.md
run_check 0 "artifacts survey: survey の成果物だけを見る（仕様ファイルを要求しない）" \
  artifacts 901 survey
run_check 1 "artifacts spec: 仕様ファイルが無ければ落ちる" artifacts 901 spec
run_check 2 "artifacts: 段の種類を省くと使い方の誤り" artifacts 901
run_check 1 "artifacts: 未知の段の種類で落ちる" artifacts 901 nonsense

# ★ 番号による免除は無い（古い番号でも成果物を見る）
run_check 1 "artifacts: 小さい番号でも免除されない" artifacts 400 spec

# ══════════════════════════════════════════════════════════════════
# 8. マージ済みコミット（★ 恒偽でないこと。旧実装は 5/5 で exit 141 だった）
# ══════════════════════════════════════════════════════════════════
setup_sandbox
git checkout -q main
echo x > x.txt; git add -A; git commit -qm "feat: x

Refs #901"
run_check 0 "artifacts feature: Refs #901 のコミットがあれば通る（★ 恒偽でない）" \
  artifacts 901 feature
run_check 1 "artifacts feature: 別番号では通らない（語境界）" artifacts 9011 feature

# ══════════════════════════════════════════════════════════════════
# 9. 使い方の誤りと「1 つも走らなかった」
# ══════════════════════════════════════════════════════════════════
setup_sandbox
run_check 2 "引数なしは使い方の誤り"
run_check 2 "未知のモードは使い方の誤り" nonsense
run_check 2 "issue に段の種類が無いと使い方の誤り" issue 901


# ══════════════════════════════════════════════════════════════════
# 10. flow/*.sh を**実際に実行する**（/review 2 回目 H-A）
#     偽の gh を PATH に置き、GitHub に触らずに経路を確かめる
# ══════════════════════════════════════════════════════════════════
make_gh_stub() {
  # make_gh_stub <spec>   spec は "番号:ラベル:状態:題名" を改行で並べたもの
  mkdir -p "$SANDBOX/bin"; rm -rf "${FAKE_GH_DIR:?}"
  printf '%s' "$1" > "$SANDBOX/issues.txt"
  cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# ★ §4 のゲートが使う呼び出し（本文・コメント・lastEditedAt・コメントの追加）は
#   issue ごとの状態を持つ tests/lib/fake_gh.py に回す
case "$*" in "issue view "*" --json body,comments,createdAt"*|"api graphql"*) exec python3 -B "$FAKE_GH" "$@";; esac
if [ "$1 $2" = "issue comment" ]; then python3 -B "$FAKE_GH" "$@" || exit 1; exit 0; fi
# 偽の gh。issues.txt を引いて必要な JSON だけ返す
f="$SANDBOX/issues.txt"
row() { grep -E "^$1:" "$f" || true; }
case "$1 $2" in
  "repo view") echo "x/y"; exit 0;;
esac
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  r="$(row "$3")"; [ -n "$r" ] || { echo "not found" >&2; exit 1; }
  IFS=: read -r _ labels state title <<< "$r"
  # ★ **`$*` 全体ではなく `--json` の値で分ける**（#555 の /review）。
  #   `$*` で見ると `--json comments` の jq に含まれる `.body` に `*body*` が当たり、
  #   コメントの問い合わせが本文を返す。`--json title,body` も題名だけを返してしまう
  json=""; prev=""
  for a in "$@"; do [ "$prev" = "--json" ] && json="$a"; prev="$a"; done
  case "$json" in
    labels)     echo "$labels";;
    state)      echo "$state";;
    title)      echo "$title";;
    createdAt)  [ -n "${GH_NO_CREATEDAT:-}" ] || echo "2020-01-01T00:00:00Z";;
    comments)   printf '%s\n' "${GH_EPIC_COMMENT:-}";;
    body)       printf '%s\n' "${GH_EPIC_BODY:-}";;
    title,body) printf '%s\n\n%s\n' "$title" "${GH_EPIC_BODY:-}";;
    *)          echo "";;
  esac
  exit 0
fi
if [ "$1" = "api" ]; then
  # ★ epic-cycle の「直近に closed になった task の closed_at」照会は**空**を返す
  #   （epic の createdAt へ落ちる経路を通す。#555）
  #   GH_CLOSED_AT_FAIL=1 で gh の失敗を再現する（#527。代入の時点で無言終了する実装を捕まえる）
  case "$*" in *closed_at*) [ -z "${GH_CLOSED_AT_FAIL:-}" ] || { echo "boom" >&2; exit 1; }; exit 0;; esac
  parent="$(echo "$2" | sed -E 's|.*/issues/([0-9]+)/sub_issues|\1|')"
  grep -E "^[0-9]+:.*:parent=$parent" "$f" | cut -d: -f1
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  # ★ epic / verdict のモードを踏むために必要な照会
  case "$*" in
    *review-integrity*) printf '%s\n' "${GH_RI_COUNT:-1}"; exit 0;;
  esac
fi
# ★ **知らない呼び出しは大声で落とす**（#555 の /review）。既定を `exit 0`（空出力）に
#   すると、新しい gh 呼び出しが増えたときテストは空の値で緑のまま通る
printf '偽 gh: 未対応の呼び出し: %s\n' "$*" >&2
exit 1
STUB
  chmod +x "$SANDBOX/bin/gh"
}

# run_flow <期待コード> <説明> <スクリプト> <引数...>
run_flow() {
  local want="$1" what="$2" script="$3"; shift 3
  local out rc
  out="$(PATH="$SANDBOX/bin:$PATH" \
         bash "$REPO_ROOT/scripts/flow/$script" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -6 | sed 's/^/        /'
  fi
}

setup_sandbox
git checkout -q -B feature/900-sandbox
make_gh_stub '900:task:OPEN:sandbox task:parent=800
901:spec:OPEN:spec 段:parent=900
902:blocked:OPEN:ラベル無し:parent=900
800:epic:OPEN:sandbox epic:parent=0
'
# 種類ラベルを持たない子があると落ちる
run_flow 1 "task-run: 種類ラベルを持たない子で落ちる" task-run.sh 900

# ラベルを直すと spec 段の案内に進む（成果物が無いので 1）
make_gh_stub '900:task:OPEN:sandbox task:parent=800
901:spec:OPEN:spec 段:parent=900
800:epic:OPEN:sandbox epic:parent=0
'
run_flow 1 "task-run: 成果物が無い spec 段では非ゼロ終了（★ exit 0 にしない）" task-run.sh 900

# 成果物を揃えると品質チェックへ進む（このサンドボックスには無いので die）
printf '# Issue #901: x\n\n中身\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: 該当なし\n'  > .spec/issues/901-auto-decisions.md
out="$(PATH="$SANDBOX/bin:$PATH" \
       bash "$REPO_ROOT/scripts/flow/task-run.sh" 900 2>&1)"; rc=$?
if [ "$(printf '%s' "$out" | grep -c '前提は揃っている' || true)" -gt 0 ]; then
  ok "task-run: 成果物が揃うと品質チェックの段へ進む"
else
  ng "task-run: 成果物が揃っても進まない（rc=$rc）"
fi

# ── #668 V1: 全ての子が closed → 完了判定＋区切りの引き継ぎ（終了コード 0）──
# ★ closed の子（401 spec・402 feature）の成果物を揃えて、全 closed の分岐に届かせる
#   spec は仕様ファイルと判断ログ、feature は main 上の 'Refs #402' のコミット
printf '# Issue #401: x\n' > .spec/issues/401-x.md
printf 'Issue #401\n停止条件: 該当なし\n' > .spec/issues/401-auto-decisions.md
git checkout -q main && git commit -q --allow-empty -m "feature 段

Refs #402" && git checkout -q -
make_gh_stub '400:task:OPEN:sandbox task:parent=800
401:spec:CLOSED:spec 段:parent=400
402:feature:CLOSED:feature 段:parent=400
800:epic:OPEN:sandbox epic:parent=0
'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -c '全ての子 issue が closed' || true)" -gt 0 ]; then
  ok "★ task-run: 全 closed の分岐に届き 0 で終わる（next_final。epic-cycle を止めない）"
else ng "task-run: 全 closed で 0 にならない（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
if [ "$(printf '%s' "$out" | grep -cE 'handoff\.sh write 400 -([[:space:]]|$)' || true)" -gt 0 ]; then
  ok "★ task-run: 全 closed で handoff.sh write 400 -（task 番号・stdin 指定。語境界つき）を案内する"
else ng "task-run: 全 closed で task への引き継ぎを案内していない"; fi
if [ "$(printf '%s' "$out" | grep -cF '/compact' || true)" -gt 0 ] \
   && [ "$(printf '%s' "$out" | grep -cF 'ワーカーは行わない' || true)" -gt 0 ]; then
  ok "★ task-run: 全 closed で /compact の案内と「ワーカーは行わない」を出す"
else ng "task-run: 全 closed の出力に /compact か「ワーカーは行わない」が無い"; fi
if [ "$(printf '%s' "$out" | grep -cE '/clear|もう一度このスクリプトを' || true)" -eq 0 ]; then
  ok "★ task-run: 全 closed で /clear も「もう一度このスクリプトを」も出さない（二重書きの防止）"
else ng "task-run: 全 closed で /clear か再呼び出しを促している"; fi

# #661: epic-cycle から降りた task-run が全 closed に届いたら、epic-cycle へ戻る案内を足す（終了コードは task-run のまま）
make_gh_stub '800:epic:OPEN:sandbox epic:parent=0
400:task:OPEN:sandbox task:parent=800
401:spec:CLOSED:spec 段:parent=400
402:feature:CLOSED:feature 段:parent=400
'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -cE 'handoff\.sh write 400 -([[:space:]]|$)' || true)" -gt 0 ] \
   && [ "$(printf '%s' "$out" | grep -cE 'handoff\.sh write 800([^0-9]|$)' || true)" -eq 0 ]; then
  ok "★ epic-cycle→task-run 全 closed: 0 で終わり、引き継ぎの書き先は task（400）で epic（800）ではない"
else ng "epic-cycle→task-run 全 closed: rc=$rc か書き先が違う: $(printf '%s' "$out" | tail -3)"; fi
# shellcheck disable=SC2016  # バッククォートは出力の文字そのもの（展開しない）
if [ "$(printf '%s' "$out" | grep -cF '後、もう一度 `bash scripts/flow/epic-cycle.sh 800` を呼ぶ（/compact はその後）' || true)" -gt 0 ]; then
  ok "★ epic-cycle→task-run 全 closed: epic-cycle.sh 800 へ戻る案内がある"
else ng "epic-cycle→task-run 全 closed: epic-cycle へ戻る案内が無い"; fi

# ★ closed 済みの task には完了判定を案内しない（#671）
make_gh_stub '900:task:CLOSED:sandbox task:parent=800
901:spec:CLOSED:spec 段:parent=900
800:epic:OPEN:sandbox epic:parent=0
'
out="$(PATH="$SANDBOX/bin:$PATH" \
       bash "$REPO_ROOT/scripts/flow/task-run.sh" 900 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *'closed 済み'* ]] \
   && [[ "$out" != *'完了判定を行う'* ]]; then
  ok "task-run: closed 済みの task には完了判定を案内しない（★ #671）"
else
  ng "task-run: closed 済みの task に完了判定を案内した（rc=$rc）"
fi

# ★ #528: 状態ラベル（user-action / blocked / out-of-date）の open な子は、既定構成の後ろの種類（docs 等）だけ飛ばす。
#   **飛ばしたことを出す。** 既定構成の段に付いていたら飛ばさずに止まる（validation より先に experiment へ進ませない）
for sl in user-action blocked out-of-date; do
  make_gh_stub "400:task:OPEN:sandbox task:parent=800
401:spec:CLOSED:spec 段:parent=400
402:feature:CLOSED:feature 段:parent=400
403:docs,$sl:OPEN:QA のフォローアップ:parent=400
404:refactor:OPEN:refactor 段:parent=400
800:epic:OPEN:sandbox epic:parent=0
"
  out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?
  if [[ "$out" == *"#403 [docs] は $sl ラベル付きなので飛ばす"* ]] && [[ "$out" == *"いまの段: #404"* ]]; then
    ok "★ task-run: $sl の docs の子（#403）を飛ばしたと出して、次の子（#404）へ進む（#528）"
  else ng "task-run: $sl の docs の子で止まる、または黙って飛ばす（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
  # 飛ばした子しか残っていない → 「全て closed」と読まない（完了判定へ進ませない）
  make_gh_stub "400:task:OPEN:sandbox task:parent=800
401:spec:CLOSED:spec 段:parent=400
402:docs,$sl:OPEN:QA のフォローアップ:parent=400
800:epic:OPEN:sandbox epic:parent=0
"
  out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$out" == *"飛ばしたものだけ"* ]] && [[ "$out" != *"全ての子 issue が closed"* ]]; then
    ok "★ task-run: 残りが $sl の子だけなら非ゼロで止まり、完了判定へ進まない（#528）"
  else ng "task-run: $sl の子が open のまま完了判定へ進んだ（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
  # 既定構成の段（spec）に付いていたら飛ばさない（後ろの feature を「いまの段」にしない）
  make_gh_stub "400:task:OPEN:sandbox task:parent=800
401:spec,$sl:OPEN:spec 段:parent=400
402:feature:OPEN:feature 段:parent=400
800:epic:OPEN:sandbox epic:parent=0
"
  out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$out" == *"既定構成の段は飛ばさない"* ]] && [[ "$out" != *"いまの段: #402"* ]]; then
    ok "★ task-run: 既定構成の段（spec）に $sl が付いていたら飛ばさずに止まる（#528 の /review）"
  else ng "task-run: $sl の spec を飛ばして feature へ進んだ（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
done
# ★ closed の子は状態ラベルが付いていても飛ばさない（成果物の検査を受ける側に残す）
make_gh_stub '400:task:OPEN:sandbox task:parent=800
401:spec,user-action:CLOSED:spec 段:parent=400
402:feature:OPEN:feature 段:parent=400
800:epic:OPEN:sandbox epic:parent=0
'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?
if [[ "$out" != *"飛ばす"* ]] && [[ "$out" == *"いまの段: #402"* ]]; then ok "task-run: closed の子は状態ラベル付きでも飛ばさない（#528）"
else ng "task-run: closed の子を飛ばした扱いにしている（rc=$rc）"; fi

# epic-cycle: open な sub-epic があると葉ではないので止まる
make_gh_stub '800:epic:OPEN:親:parent=0
801:epic:OPEN:sub-epic:parent=800
900:task:OPEN:t:parent=800
'
run_flow 1 "epic-cycle: open な sub-epic があると葉ではないので止まる" epic-cycle.sh 800

# sub-epic を閉じると task-run へ降りる
make_gh_stub '800:epic:OPEN:親:parent=0
801:epic:CLOSED:sub-epic:parent=800
900:task:OPEN:t:parent=800
901:spec:OPEN:spec 段:parent=900
'
out="$(PATH="$SANDBOX/bin:$PATH" \
       bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"
if [ "$(printf '%s' "$out" | grep -c 'いまの段: #901' || true)" -gt 0 ]; then
  ok "epic-cycle: 葉なら task-run.sh へ降りる（受け渡しが動く）"
else
  ng "epic-cycle: task-run.sh へ降りない"
fi

# ══════════════════════════════════════════════════════════════════
# 10b. open な task が 0 件の epic（★ epic / verdict のモードを踏む唯一の経路）
#      epic-cycle.sh は open な task があると task-run へ降りて return するので、
#      **0 件の fixture が無いと 3 モードは一度も実行されない**
# ══════════════════════════════════════════════════════════════════
make_gh_stub '800:epic:OPEN:親:parent=0
900:task:CLOSED:閉じた task:parent=800
'
export GH_EPIC_BODY='## 完了条件

- [ ] 条件その一が満たされている
- [ ] 条件その二が満たされている
'
# ★ まず判定コメントが**無い**場合（verdict が落ちる）
export GH_EPIC_COMMENT=''
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$(printf '%s' "$out" | grep -c 'issue に紐づかないコミット' || true)" -gt 0 ]; then
  ok "★ epic モードを踏む（紐づかないコミットを数える）"
else ng "epic モードに到達していない: $(printf '%s' "$out" | tail -3)"; fi
if [ "$(printf '%s' "$out" | grep -c 'chore の単独 issue' || true)" -eq 0 ]; then
  ok "chore の単独 issue を数えない（epic の判定に引用させない）"
else ng "chore の単独 issue を数えている"; fi
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c "'## 判定' の見出しを含むコメント" || true)" -gt 0 ]; then
  ok "★ verdict モードを踏み、判定コメントが無ければ非ゼロ"
else ng "verdict が判定コメントの不在を落としていない（rc=$rc）"; fi
# #668 V3: 判定コメントが揃っていない（next_fail）ときは区切りの引き継ぎを出さない
if [ "$(printf '%s' "$out" | grep -cE 'handoff\.sh write|/compact' || true)" -eq 0 ]; then
  ok "★ epic-cycle: 判定コメントが揃っていないときは引き継ぎを案内しない"
else ng "epic-cycle: next_fail の段で引き継ぎを案内している"; fi

# ★ 判定コメントを揃えると通る（恒偽でないことの確認）
export GH_EPIC_COMMENT='## 判定

- 条件その一が満たされている → 達成
- 条件その二が満たされている → 達成

'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$(printf '%s' "$out" | grep -c '完了条件を 1 項目ずつ引用している' || true)" -gt 0 ]; then
  ok "★ 判定コメントが完了条件を引用していれば verdict が通る（恒偽でない）"
else ng "揃った判定コメントでも verdict が通らない: $(printf '%s' "$out" | tail -5)"; fi
# #668 V3: 最後の next（判断）には epic への引き継ぎを足し、末尾の再呼び出しは付けない
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -cE 'handoff\.sh write 800 -([[:space:]]|$)' || true)" -gt 0 ] \
   && [ "$(printf '%s' "$out" | grep -cF '/compact' || true)" -gt 0 ]; then
  ok "★ epic-cycle: 最後の出力に handoff.sh write 800（epic 番号）と /compact がある（0 で終わる）"
else ng "epic-cycle: 最後の出力に epic への引き継ぎが無い（rc=$rc）"; fi
if [ "$(printf '%s' "$out" | grep -cE '/clear|もう一度このスクリプトを' || true)" -eq 0 ]; then
  ok "★ epic-cycle: 最後の出力で /clear も「もう一度このスクリプトを」も出さない"
else ng "epic-cycle: 最後の出力で /clear か再呼び出しを促している"; fi

# ★ 引用が 1 項目欠けると落ちる（項目ごとに単独で落ちることの確認）
export GH_EPIC_COMMENT='## 判定

- 条件その一が満たされている → 達成

'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"
if [ "$(printf '%s' "$out" | grep -c '完了条件が引用されていない' || true)" -gt 0 ]; then
  ok "★ 引用の欠けた完了条件を単独で落とす"
else ng "引用が欠けても通ってしまう"; fi

# ★ 番号付き列挙の完了条件も項目として読む（#742。epic #614 の形。継続行・入れ子は項目にしない）
export GH_EPIC_BODY='## 完了条件

**前置きの段落は項目ではない**

0. ★ **番号ゼロの条件が揃っている**（上記の形式）。
   継続行は項目ではない
1. **番号一の条件が列挙されている。**
   - 入れ子の箇条書きも項目ではない

---
'
export GH_EPIC_COMMENT='## 判定

- ★ **番号ゼロの条件が揃っている**（上記の形式）。 → 達成
- **番号一の条件が列挙されている。** → 達成

'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -c '完了条件が引用されている' || true)" -eq 2 ]; then
  ok "★ 番号付き列挙の完了条件を 2 項目と読み、引用が揃えば verdict が通る"
else ng "番号付き列挙の完了条件を読めていない（rc=$rc）: $(printf '%s' "$out" | tail -5)"; fi
export GH_EPIC_COMMENT='## 判定

- ★ **番号ゼロの条件が揃っている**（上記の形式）。 → 達成

'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c '完了条件が引用されていない: \*\*番号一の条件' || true)" -gt 0 ]; then
  ok "★ 番号付き列挙で引用が 1 項目欠けると落ちる"
else ng "番号付き列挙で引用が欠けても通ってしまう（rc=$rc）"; fi
export GH_EPIC_BODY='## 完了条件

- [ ] 条件その一が満たされている
- [ ] 条件その二が満たされている
'

# ★ 乖離検査を走らせていなければ落ちる（この門はこれまで一度も踏まれていなかった）
export GH_RI_COUNT=0
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c '乖離検査を走らせていない' || true)" -gt 0 ]; then
  ok "★ このサイクルで乖離検査を走らせていなければ落ちる"
else ng "乖離検査の門が効いていない（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
unset GH_RI_COUNT

# ★ epic の計数が失敗したら握り潰さない（gh の失敗を「0 件」と読まない）
export GH_NO_CREATEDAT=1
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c 'epic の計数が失敗した' || true)" -gt 0 ]; then
  ok "★ epic の計数が失敗したら落ちる（gh の失敗を 0 件と読まない）"
else ng "epic の計数の失敗を握り潰している（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
unset GH_NO_CREATEDAT

# ★ #527: サイクル開始時刻（closed_at）の照会が失敗したら、**理由を出して**落ちる
#   （`since="$(gh … 2>/dev/null)"` は set -e 下で代入の時点で終わり、何も出さない）
export GH_CLOSED_AT_FAIL=1
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -c 'closed_at 取得 が失敗した' || true)" -gt 0 ]; then
  ok "★ closed_at の照会が失敗したら理由を出して落ちる（無言終了で規律違反と区別できない、を防ぐ。#527）"
else ng "closed_at の照会の失敗が無言終了になる（rc=$rc）: $(printf '%s' "$out" | tail -3)"; fi
unset GH_CLOSED_AT_FAIL

unset GH_EPIC_BODY GH_EPIC_COMMENT

# ★ gh が失敗したら黙って通さない（C3 の回帰検査）
make_gh_stub '800:epic:OPEN:親:parent=0'
run_flow 1 "flow: gh が引けない issue を指すと落ちる（黙って通さない）" task-run.sh 777

# ★ QUALITY_SCOPE の裏口（H4 の回帰検査）
# shellcheck disable=SC2016  # $1 は bash -c の中で展開させる
scope="$(QUALITY_SCOPE=docs QUALITY_BASE_BRANCH=HEAD bash -c \
  '. "$1/scripts/flow/lib.sh"; scope_for feature' _ "$REPO_ROOT" 2>/dev/null)"
if [ "$scope" = "all" ]; then
  ok "QUALITY_SCOPE: feature 段では環境の docs を無視して all になる"
else
  ng "QUALITY_SCOPE: feature 段で '$scope' になった（all のはず）"
fi

cd "$REPO_ROOT" || exit 1

cd "$REPO_ROOT" || exit 1
echo
printf '成立 %d / 不成立 %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
