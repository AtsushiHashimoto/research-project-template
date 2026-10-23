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
# ★ 品質ゲートの中から走ると QUALITY_* を継承する。記録の鍵の検査が親の値で変わらないよう切る
unset QUALITY_FULL_SCAN QUALITY_SCOPE QUALITY_BASE_BRANCH

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
3. 作業場所: メインリポジトリ <メインリポジトリの絶対パス>。worktree は `worktrees/task<TASK>`
（親が task でない issue は `worktrees/issue<N>`）。まだ無いので、`issue-start.sh` の出力の `cd` 行に従って移る。
書き換えてよい本文は task の `## 未確定` 節の行だけ。task へのコメント（判定・停止の解消）は書いてよい。
`## 目標の状態`（goal）と他の issue の本文は編集しない。goal の空欄・goal ゲートの FAIL では needs-user を返す。
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
# ★ §4 のゲートが使う呼び出し（本文・コメント・コメントの追加）は
#   issue ごとの状態を持つ tests/lib/fake_gh.py に回す
case "$*" in "issue view "*" --json body,comments,createdAt"*) exec python3 -B "$FAKE_GH" "$@";; esac
if [ "$1 $2" = "issue comment" ]; then [ -z "${GH_COMMENT_FAIL:-}" ] || { echo "boom" >&2; exit 1; }
  python3 -B "$FAKE_GH" "$@" || exit 1; exit 0; fi
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
    parent)     p="${title##*:parent=}"; [ "$p" = "$title" ] || [ "$p" = 0 ] || echo "$p";;
    *)          echo "";;
  esac
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then [ -z "${GH_PR_VIEW_FAIL:-}" ] || { echo "boom" >&2; exit 1; }
  cat "$SANDBOX/pr_body.txt" 2>/dev/null; exit 0; fi
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

# gh_put <N> <本文> [<コメント> <createdAt>]...
#   $GH_COMMENT_EDITED=1 でコメントを「編集された」にする。$GH_STATE_REASON で閉じた理由
gh_put() {
  local n="$1"; shift; mkdir -p "$FAKE_GH_DIR"
  python3 -c 'import json,os,sys; a=sys.argv[2:]
d={"body":a[0],"comments":[{"body":a[i],"createdAt":a[i+1]} for i in range(1,len(a),2)]}
if os.environ.get("GH_COMMENT_EDITED"): [c.update(includesCreatedEdit=True) for c in d["comments"]]
if os.environ.get("GH_STATE_REASON"): d["stateReason"]=os.environ["GH_STATE_REASON"]
json.dump(d,open(sys.argv[1],"w"),ensure_ascii=False)' "$FAKE_GH_DIR/$n.json" "$@"
}
has() { [ "$(printf '%s' "$1" | grep -cF -e "$2" || true)" -gt 0 ]; }
# epic の判定コメントを置く（verdict は見出しを本物と同じ照合で引くので、偽 gh の issue ごとの状態に置く）
epic_comment() {
  export GH_EPIC_COMMENT="$1"
  if [ -n "$1" ]; then gh_put 800 "${GH_EPIC_BODY:-}" "$1" 2020-02-03T00:00:00Z; else gh_put 800 "${GH_EPIC_BODY:-}"; fi
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

# ★ 品質チェックの後の案内は、PR を作ってから本文に書く順（無い PR の本文には書けない）
git add .spec/issues/901-x.md .spec/issues/901-auto-decisions.md && git commit -qm "spec

Refs #901"
printf '%s\n' "$(bash -c ". '$LIB'; quality_record_key \"\$(scope_for spec)\"")" > "$(git rev-parse --git-dir)/flow-quality-passed"
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 900 2>&1)"; rc=$?
order="$(printf '%s\n' "$out" | awk '/commit\.sh push/&&!a{a=NR} /gh pr create/&&!b{b=NR} /## \/review 結果/&&!c{c=NR} /## 仕様整合/&&!d{d=NR} /gh pr edit/&&!e{e=NR} /issue-finish\.sh 901 900/&&!f{f=NR}
  END{print (a&&a<b&&b<c&&c<d&&d<e&&e<f)?"ok":"ng " a" "b" "c" "d" "e" "f}')"
if [ "$order" = ok ]; then ok "★ 品質チェックの後: stage・push → gh pr create → /review・仕様整合 → gh pr edit → issue-finish の順"
else ng "品質チェックの後の案内の順が違う（rc=$rc、行番号 ${order#ng }）"; printf '%s\n' "$out" | tail -15 | sed 's/^/        /'; fi

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
# ★ 親 epic があれば、再開は epic-cycle（次の task は epic-cycle が選ぶ）
if has "$out" "再開は \`bash scripts/flow/epic-cycle.sh 800\`"; then ok "★ task-run: 全 closed・親 epic あり → 再開は epic-cycle.sh 800"
else ng "task-run: 親 epic があるのに再開を epic-cycle.sh で案内していない"; fi
make_gh_stub '400:task:OPEN:sandbox task
401:spec:CLOSED:spec 段:parent=400
402:feature:CLOSED:feature 段:parent=400
'
out2="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"
if has "$out2" "再開は \`bash scripts/flow/task-run.sh 400\`"; then ok "（対照）親 epic が無ければ再開は task-run.sh 400"
else ng "（対照）親 epic が無いのに task-run.sh 400 で再開を案内していない: $(printf '%s' "$out2" | tail -3)"; fi

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
epic_comment ''
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
epic_comment '## 判定

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

# ★ 見出しは完全一致（「## 判定の前に」は判定ではない。python 側の照合と同じ）
epic_comment '## 判定の前にメモ

- 条件その一が満たされている → 達成
- 条件その二が満たされている → 達成
'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "'## 判定' の見出しを含むコメント"; then ok "★ verdict: 「## 判定の前にメモ」を判定コメントと読まない"
else ng "verdict: 見出しが違うコメントを判定と読んだ（rc=$rc）"; fi

# ★ 引用が 1 項目欠けると落ちる（項目ごとに単独で落ちることの確認）
epic_comment '## 判定

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
epic_comment '## 判定

- ★ **番号ゼロの条件が揃っている**（上記の形式）。 → 達成
- **番号一の条件が列挙されている。** → 達成

'
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -c '完了条件が引用されている' || true)" -eq 2 ]; then
  ok "★ 番号付き列挙の完了条件を 2 項目と読み、引用が揃えば verdict が通る"
else ng "番号付き列挙の完了条件を読めていない（rc=$rc）: $(printf '%s' "$out" | tail -5)"; fi
epic_comment '## 判定

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

# ══════════════════════════════════════════════════════════════════
# 11. §4 の判断ゲート。**ゲートごとに通る場合と落ちる場合**を置き、落ちたときの出力に
#     3 点（足りないもの・書く行・再実行コマンド）があることを grep する。
#     issue ごとの本文・コメントは tests/lib/fake_gh.py（$FAKE_GH_DIR/<N>.json）が返す
# ══════════════════════════════════════════════════════════════════
# stop3 <説明> <rc> <出力> <足りないもの> <書く行> <再実行コマンド>
stop3() {
  if [ "$2" -ne 0 ] && has "$3" "$4" && has "$3" "書く行: $5" && has "$3" "再実行: $6"; then ok "$1"
  else ng "$1（rc=$2。足りないもの・書く行・再実行のどれかが無い）"; printf '%s\n' "$3" | grep -E 'FAILED|書く行|再実行' | sed -n '1,8p' | sed 's/^/        /'; fi
}
nostop() {  # nostop <説明> <出力> <止まった理由の語>
  if ! has "$2" "止まった理由: $3"; then ok "$1"; else ng "$1"; printf '%s\n' "$2" | grep -E 'FAILED' | sed -n '1,5p' | sed 's/^/        /'; fi
}
tr400() { out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 400 2>&1)"; rc=$?; }
GOAL_OK='## 目標の状態

- 成功条件: 砂場の測定が 1 回通ること
- negative の意味: 通らなければ実装が壊れている'
# goal ゲートの判定は「## 目標の状態」の hash で本文と結びつく（計算は本物の goal_hash）
ghash() { python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from check_discipline_md import goal_hash; print(goal_hash(sys.argv[2]))' "$REPO_ROOT/scripts" "$1"; }
GATE_OK="## goal ゲート

- 目標の状態の hash: $(ghash "$GOAL_OK")
- G1b: PASS — 1 文の述語
- G3: PASS — 残る
- G4: PASS — 1 つ"
RERUN='bash scripts/flow/task-run.sh 400'
GOALW='task #400 の goal'

setup_sandbox
git update-ref refs/remotes/origin/main main   # 解消済みの根拠のファイルを origin/main で引く
ROWS='800:epic:OPEN:epic:parent=0
400:task:OPEN:sandbox task:parent=800
401:spec:OPEN:spec 段:parent=400
402:validation:OPEN:validation 段:parent=400
'
make_gh_stub "$ROWS"

# ── goal の空欄 ──
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
nostop "goal: 成功条件・negative の意味・判定がそろえば止まらない" "$out" "$GOALW"
if has "$out" "いまの段: #401"; then ok "goal: 通ったら子の段へ進む"; else ng "goal: 通っても子の段へ進まない"; fi
for v in '<1 文の述語>' 'TBD' '未定' '   '; do
  gh_put 400 "## 目標の状態

- 成功条件: $v
- negative の意味: x" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
  stop3 "goal: 成功条件が「$v」なら空とみなして止まる" "$rc" "$out" "「成功条件」が空" "- 成功条件: <1 文の合否の述語>" "$RERUN"
done
if has "$out" "needs-user で返す（goal はユーザーが書く）" && has "$out" "書き換えてよい本文は「## 未確定」節の行だけ"; then
  ok "goal の停止: ワーカーが直してよいのは「## 未確定」だけで、goal の空欄は needs-user と書く"
else ng "goal の停止に、ワーカーが書き換えてよい範囲（## 未確定 だけ・goal は needs-user）が無い"; fi
order="$(printf '%s\n' "$out" | awk '/1\. 先に上の「足りないもの」を直す/&&!a{a=NR} /2\. 1 が済んでから goal の中身の判定/&&!b{b=NR} END{print (a&&a<b)?"ok":"ng"}')"
if [ "$order" = ok ]; then ok "goal の停止: 1. 空欄を直す → 2. その後で判定のサブエージェント の順に書く"
else ng "goal の停止の手順が「1. 直す → 2. 判定を起動」の順になっていない"; fi
# ★ 裸の記号を出さない: 停止条件は定義のファイルを名指しする、段の番号では呼ばない
cic() { local b; b="$(grep -vE '^[[:space:]]*#' "$1")"; printf '%s' "$b" | grep -cE -e "$2" || true; }
f=task-run.sh
if [ "$(cic "$REPO_ROOT/scripts/flow/$f" '"[^"]*段 [0-9]')" -eq 0 ] \
   && [ "$(cic "$REPO_ROOT/scripts/flow/$f" '"[^"]*S1〜S8')" = "$(cic "$REPO_ROOT/scripts/flow/$f" '"[^"]*auto-reviewer\.md の停止条件 S1〜S8')" ]; then
  ok "$f の案内は「段 N」と裸の S1〜S8 を使わない（定義のファイルを名指しする）"
else ng "$f の案内に「段 N」か、定義のファイルを添えない S1〜S8 がある"; fi
gh_put 400 "## 目標の状態

- 成功条件: x" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
stop3 "goal: negative の意味の行が無いと止まる" "$rc" "$out" "「negative の意味」の行が無い" "- negative の意味:" "$RERUN"
gh_put 400 "## 背景

なし" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
stop3 "goal: 「## 目標の状態」節が無いと止まる" "$rc" "$out" "「## 目標の状態」節が無い" "## 目標の状態" "$RERUN"
# ★ 落ちた行を 1 回で全部出す（成功条件の空と goal ゲートの不在が同じ停止に並ぶ）
gh_put 400 "## 目標の状態

- 成功条件: TBD
- negative の意味: x"; tr400
if has "$out" "「成功条件」が空" && has "$out" "goal ゲートの判定コメント"; then ok "★ goal: 落ちた行を 1 回の停止ですべて出す"
else ng "goal: 落ちた行を 1 つずつしか出さない"; fi
# ★ 止まった理由を task に 1 回だけコメントする（JST・同じ内容なら書かない）
n1="$(grep -c '^## 停止: ' "$FAKE_GH_DIR/comments.log" || true)"; tr400
n2="$(grep -c '^## 停止: ' "$FAKE_GH_DIR/comments.log" || true)"
if [ "$n1" -ge 1 ] && [ "$n1" = "$n2" ] && [ "$(grep -c 'JST$' "$FAKE_GH_DIR/comments.log" || true)" -ge 1 ]; then
  ok "★ 停止の理由を task にコメントし（JST の時刻つき）、同じ停止の再実行では書き足さない"
else ng "停止のコメント: 1 回目 $n1 件・2 回目 $n2 件（1 以上で同数のはず）か JST が無い"; fi

# ── goal の中身の判定（verification のサブエージェントが書く）──
gh_put 400 "$GOAL_OK"; tr400
stop3 "goal ゲート: 判定コメントが無いと止まる" "$rc" "$out" "goal ゲートの判定コメント" "- G1b: PASS —" "$RERUN"
if has "$out" "resolve-model.sh verification" && has "$out" "bash scripts/read-premises.sh 400" \
   && has "$out" "成功条件が 1 文の合否の述語"; then ok "goal ゲート: 停止文が起動文（verification・前提・判定の中身）を出す"
else ng "goal ゲート: 停止文に起動文が無い"; fi
GOAL_NEW="${GOAL_OK/1 回通ること/2 回通ること}"
gh_put 400 "$GOAL_NEW" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
stop3 "goal ゲート: 判定の hash がいまの「## 目標の状態」と違うと止まる（書く hash を出す）" "$rc" "$out" \
  "いまの「## 目標の状態」（hash $(ghash "$GOAL_NEW")）に対するものでない" "目標の状態の hash: $(ghash "$GOAL_NEW")" "$RERUN"
gh_put 400 "$GOAL_OK

## 未確定

- 閾値の値 → #402" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
nostop "goal ゲート: 「## 未確定」だけを書き換えても判定し直さなくてよい（hash は目標の状態だけ）" "$out" "$GOALW"
gh_put 400 "$GOAL_OK" "${GATE_OK/- 目標の状態の hash: */- G0: x}" 2020-02-01T00:00:00Z; tr400
stop3 "goal ゲート: 判定に hash の行が無いと止まる" "$rc" "$out" "判定の hash: 無し" "目標の状態の hash: $(ghash "$GOAL_OK")" "$RERUN"
GH_COMMENT_EDITED=1 gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
stop3 "goal ゲート: 判定コメントが編集されていると止まる（新しいコメントで出し直す）" "$rc" "$out" "判定コメントが編集されている" "- G1b: PASS —" "$RERUN"
gh_put 400 "$GOAL_OK" "$GATE_OK
- G3: FAIL — 残らない" 2020-02-01T00:00:00Z; tr400
stop3 "goal ゲート: PASS の行があっても FAIL の行が 1 つでもあれば止まる" "$rc" "$out" "G3（未確定に言及する語を削っても、何を作り何を測るかが残る）が FAIL" "- G3: PASS —" "$RERUN"
gh_put 400 "$GOAL_OK" "${GATE_OK/- G3: PASS — 残る/- G3: FAIL — 残らない}" 2020-02-01T00:00:00Z; tr400
stop3 "goal ゲート: G3 が FAIL なら止まる" "$rc" "$out" "G3（未確定に言及する語を削っても" "- G3: PASS —" "$RERUN"
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z "## goal ゲート

- 目標の状態の hash: $(ghash "$GOAL_OK")
- G1b: PASS — x" 2020-02-02T00:00:00Z; tr400
stop3 "goal ゲート: **最新の**判定に G4 が無ければ止まる（古い判定で通さない）" "$rc" "$out" "G4（解釈が 1 つに定まる）" "- G4: PASS —" "$RERUN"

# ── 未確定の担当 ──
und() { gh_put 400 "$GOAL_OK

## 未確定

$1" "$GATE_OK" 2020-02-01T00:00:00Z "${@:2}"; tr400; }
und '- 閾値の値 → **#402**（補足）'
nostop "未確定: 担当が子の #番号なら通る（装飾と補足は無視）" "$out" "$GOALW"
und '- 閾値の値 → validation'
nostop "未確定: 担当が種類ラベルでその子があれば通る" "$out" "$GOALW"
und '- 閾値の値 → experiment'
stop3 "未確定: 担当の種類の子が無いと止まる" "$rc" "$out" "担当 experiment の子が task #400 に無い" "" "$RERUN"
und '- 閾値の値 -> #999'
stop3 "未確定: 担当の #番号が task の子でないと止まる" "$rc" "$out" "担当 #999 が task #400 の子でない" "- 閾値の値 → #<task #400 の子の番号>" "$RERUN"
und '- 閾値の値'
stop3 "未確定: 担当が無いと止まる" "$rc" "$out" "担当（→ の後の種類ラベルか #番号）が無い" "- 閾値の値 → <種類ラベル" "$RERUN"
make_gh_stub "${ROWS/402:validation:OPEN/402:validation,user-action:OPEN}"
und '- 閾値の値 → #402'
stop3 "未確定: 担当に user-action が付いていると止まる" "$rc" "$out" "状態ラベル付き: #402(user-action)" "" "$RERUN"
make_gh_stub "$ROWS"
und ''
nostop "未確定: 節が空なら続行する" "$out" "$GOALW"
# shellcheck disable=SC2016  # バッククォートは本文の装飾そのもの（展開させない）
und '- 閾値の値 → `validation`（補足）'
nostop "未確定: 担当の装飾（バッククォート）を落として読む" "$out" "$GOALW"
make_gh_stub "${ROWS/402:validation:OPEN/402:validation,blocked:OPEN}"
und '- 閾値の値 → #402'
stop3 "未確定: 担当に blocked が付いていると止まる（task-run が飛ばすので誰も解消しない）" "$rc" "$out" "状態ラベル付き: #402(blocked)" "" "$RERUN"
make_gh_stub "$ROWS"
und '- 閾値の値 → #402
  - 入れ子の補足（担当なし）
1. 番号の項目 → #402'
nostop "未確定: 行頭の - と N. を項目にし、字下げした入れ子は項目にしない" "$out" "$GOALW"
if grep -qx -- '1. 番号の項目 → #402\|- 番号の項目 → #402' "$FAKE_GH_DIR/comments.log" && ! grep -q '入れ子の補足' "$FAKE_GH_DIR/comments.log"; then
  ok "未確定: 番号の項目は記録し、入れ子は記録しない"
else ng "未確定: 番号の項目の記録か入れ子の除外が違う"; fi
make_gh_stub "$ROWS"
und '- 閾値の値 -> #999'
if [ "$rc" -ne 0 ] && grep -qx -- '- 閾値の値 → #999' "$FAKE_GH_DIR/comments.log"; then
  ok "★ 未確定: 他の検査が落ちた回でも、初めて見た項目を記録する"
else ng "未確定: 落ちた回に記録を書いていない（rc=$rc）"; fi

# ── 未確定の記録と、行を消して逃げることの検出 ──
make_gh_stub "$ROWS"   # 記録の数を数えるので、前の検査が書いたコメントを消す
und '- 閾値の値 → #402'
if [ "$(grep -c '^## 未確定（記録）' "$FAKE_GH_DIR/comments.log" || true)" = 1 ] && grep -qx -- '- 閾値の値 → #402' "$FAKE_GH_DIR/comments.log"; then
  ok "未確定: 初回の PASS で項目名を「## 未確定（記録）」にコメントする"
else ng "未確定: 記録のコメントが無い"; fi
tr400
if [ "$(grep -c '^## 未確定（記録）' "$FAKE_GH_DIR/comments.log" || true)" = 1 ]; then ok "未確定: 同じ内容の記録は 1 回だけ"
else ng "未確定: 記録を 2 回書いた"; fi
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["body"]=sys.argv[2]; json.dump(d,open(p,"w"),ensure_ascii=False)' \
  "$FAKE_GH_DIR/400.json" "$GOAL_OK"; tr400
stop3 "★ 未確定: 記録にある項目を本文から消すと止まる" "$rc" "$out" "未確定「閾値の値」が本文の「## 未確定」から消えている" "- 閾値の値 解消不能（理由:" "$RERUN"

# ── 再照合（担当がすべて closed になった未確定の行）──
make_gh_stub "${ROWS/402:validation:OPEN/402:validation:CLOSED}"
und '- 閾値の値 → #402'
stop3 "再照合: 担当がすべて closed なのに書き換えていないと止まる" "$rc" "$out" "解消したかどうかが書かれていない" "- 閾値の値 解消済み（→ #402," "$RERUN"
REC='## 未確定（記録）

- 閾値の値 → #402'
und '- 閾値の値 解消済み（→ #402, base.txt §2）' "$REC" 2020-01-20T00:00:00Z
nostop "再照合: 解消済み（closed な担当 #N と origin/main にあるファイル）なら通る（担当は記録から）" "$out" "$GOALW"
und '- 閾値の値 → #402 解消済み（→ #402, base.txt）'
nostop "再照合: 解消済み（担当を行に残した形）なら通る" "$out" "$GOALW"
und '- 閾値の値 解消済み（→ #402, base.txt）'
stop3 "再照合: 担当が行にも記録にも無いと止まる" "$rc" "$out" "担当が分からない" "- 閾値の値 → <担当> 解消済み（→ #<担当の番号>" "$RERUN"
und '- 閾値の値 解消済み（→ #77, base.txt）' "$REC" 2020-01-20T00:00:00Z
stop3 "再照合: 根拠の #N が担当でない（PR の番号など）と止まる（rc 2 にしない）" "$rc" "$out" "根拠 #77 が担当（#402）のどれでもない" "- 閾値の値 解消済み（→ #402," "$RERUN"
if has "$out" "検査そのものが失敗した"; then ng "再照合: 担当でない #N で検査が壊れた（exit 2）"; else ok "再照合: 担当でない #N は gh を引かずに止める"; fi
git checkout -q main && mkdir -p dd && echo x > dd/f.txt && git add dd/f.txt && git commit -qm dd \
  && git update-ref refs/remotes/origin/main main && git checkout -q -
und '- 閾値の値 解消済み（→ #402, dd）' "$REC" 2020-01-20T00:00:00Z
stop3 "再照合: 根拠がディレクトリだと止まる（blob だけ）" "$rc" "$out" "dd が origin/main に無い" "- 閾値の値 解消済み（→ #402, <origin/main にあるファイル>）" "$RERUN"
und '- 閾値の値 解消済み（→ #402, nope.txt）' "$REC" 2020-01-20T00:00:00Z
stop3 "再照合: 根拠のファイルが origin/main に無いと止まる（git cat-file -e）" "$rc" "$out" "nope.txt が origin/main に無い" "- 閾値の値 解消済み（→ #402, <origin/main にあるファイル>）" "$RERUN"
make_gh_stub "$ROWS"
und '- 閾値の値 解消済み（→ #402, base.txt）' "$REC" 2020-01-20T00:00:00Z
stop3 "再照合: 解消済みの根拠の #N が closed でないと止まる" "$rc" "$out" "根拠 #402 が closed でない" "- 閾値の値 解消済み（→ #<closed な issue>" "$RERUN"
und '- 閾値の値 解消不能（理由: 測れない）'
nostop "再照合: 解消不能（理由つき）なら通る" "$out" "$GOALW"

# ── task の判定の形（task を閉じる前）──
printf '# Issue #401: x\n' > .spec/issues/401-x.md
printf 'Issue #401\n停止条件: 該当なし\n' > .spec/issues/401-auto-decisions.md
git checkout -q main && git commit -q --allow-empty -m "validation 段

Refs #402" && git update-ref refs/remotes/origin/main main && git checkout -q -
make_gh_stub '800:epic:OPEN:epic:parent=0
400:task:OPEN:sandbox task:parent=800
401:spec:CLOSED:spec 段:parent=400
402:validation:CLOSED:validation 段:parent=400
'
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z; tr400
stop3 "判定の形: 全 closed で判定コメントが無いと止まる" "$rc" "$out" "判定コメント（「## 判定」）が無い" "結果:" "$RERUN"
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z "## 判定

結果: たぶん良い
- 砂場の測定が 1 回通ること → 満たした" 2020-02-02T00:00:00Z; tr400
stop3 "判定の形: 結果の行が 3 値のどれでもないと止まる" "$rc" "$out" "「結果: positive」" "結果: <positive|negative|未達成>" "$RERUN"
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z "## 判定

結果: positive" 2020-02-02T00:00:00Z; tr400
stop3 "判定の形: 成功条件を引用していないと止まる" "$rc" "$out" "成功条件を引用していない: 砂場の測定が 1 回通ること" "- 成功条件: 砂場の測定が 1 回通ること →" "$RERUN"
gh_put 400 "$GOAL_OK" "$GATE_OK" 2020-02-01T00:00:00Z "## 判定

結果: negative
- 砂場の測定が 1 回通ること → 満たさない" 2020-02-02T00:00:00Z; tr400
if [ "$rc" -eq 0 ] && has "$out" "gh issue close 400"; then ok "判定の形: 揃えば task を閉じる案内（0 で終わる）"
else ng "判定の形: 揃っても閉じる案内に進まない（rc=$rc）"; fi

# ── 全部 negative（epic の判定）──
make_gh_stub '800:epic:OPEN:epic:parent=0
400:task:CLOSED:t1:parent=800
410:task:CLOSED:t2:parent=800
'
neg() { gh_put "$1" "$GOAL_OK" "## 判定

結果: $2" 2020-02-02T00:00:00Z; }
export GH_EPIC_BODY='## 完了条件

- [ ] 条件その一'
export GH_EPIC_COMMENT='## 判定

- 条件その一 → 未達成'
ec() { out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/epic-cycle.sh" 800 2>&1)"; rc=$?; }
neg 400 negative; neg 410 negative; gh_put 800 "$GH_EPIC_BODY" "$GH_EPIC_COMMENT" 2020-02-03T00:00:00Z; ec
stop3 "全部 negative: 確認の節が無いと止まる" "$rc" "$out" "結果がすべて negative" "## 全部 negative の確認" "bash scripts/flow/epic-cycle.sh 800"
gh_put 800 "$GH_EPIC_BODY" "$GH_EPIC_COMMENT

## 全部 negative の確認

planted 効果を入れた砂場で検出できることを確かめ直した" 2020-02-03T00:00:00Z; ec
if [ "$rc" -eq 0 ] && ! has "$out" "止まった理由"; then ok "全部 negative: 確認の節があれば通る"
else ng "全部 negative: 確認の節があっても止まる（rc=$rc）"; fi
neg 410 positive; gh_put 800 "$GH_EPIC_BODY" "$GH_EPIC_COMMENT" 2020-02-03T00:00:00Z; ec
if [ "$rc" -eq 0 ]; then ok "全部 negative: 1 件でも negative でなければ確認を求めない"
else ng "全部 negative: positive が混ざっても止まる（rc=$rc）"; fi
neg 410 'negative（検出力の不足）'; ec
stop3 "全部 negative: 「結果: negative（…）」も negative と数える" "$rc" "$out" "結果がすべて negative" "## 全部 negative の確認" "bash scripts/flow/epic-cycle.sh 800"
gh_put 410 "$GOAL_OK"; ec
stop3 "全部 negative: 閉じた task に判定が無いと止まる（数えずに通さない）" "$rc" "$out" "閉じた task #410 に判定が無い" "結果: <positive|negative|未達成>" "bash scripts/flow/epic-cycle.sh 800"
make_gh_stub '800:epic:OPEN:epic:parent=0
410:task:CLOSED:t2:parent=800
420:task:CLOSED:t3:parent=800
'
neg 410 negative; GH_STATE_REASON=NOT_PLANNED neg 420 positive; gh_put 800 "$GH_EPIC_BODY" "$GH_EPIC_COMMENT" 2020-02-03T00:00:00Z; ec
stop3 "全部 negative: not planned で閉じた task は数えない" "$rc" "$out" "閉じた task 1 件の結果がすべて negative" "## 全部 negative の確認" "bash scripts/flow/epic-cycle.sh 800"
unset GH_EPIC_BODY GH_EPIC_COMMENT

# ── 仕様レビュー（spec の判断ログの停止条件）──
setup_sandbox
printf '# Issue #901: x\n' > .spec/issues/901-x.md
printf 'Issue #901\n停止条件: S2（成功条件が測れない）\n' > .spec/issues/901-auto-decisions.md
out="$(bash "$CHECK" issue 901 spec 900 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "停止条件に該当している"; then ok "仕様レビュー: 判断ログが停止条件に該当していると止まる"
else ng "仕様レビュー: 停止条件 S2 の判断ログで通る（rc=$rc）"; fi
printf 'Issue #901\n停止条件の検査をした\n' > .spec/issues/901-auto-decisions.md
out="$(bash "$CHECK" issue 901 spec 900 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "書く行: 停止条件: 該当なし"; then ok "仕様レビュー: 「停止条件: 該当なし」の行が無いと止まる（書く行を出す）"
else ng "仕様レビュー: 停止条件の行が無くても通る（rc=$rc）"; fi
printf 'Issue #901\n- 停止条件チェック: **該当なし**\n' > .spec/issues/901-auto-decisions.md
run_check 0 "仕様レビュー: 停止条件チェック: 該当なし（装飾つき）なら通る" issue 901 spec 900
# ★ auto-reviewer の判断ログは表の形（| 停止条件チェック | X |）で書かれる。値の読み方を形ごとに固定する
while IFS='|' read -r want line; do
  printf 'Issue #901\n%s\n' "$line" > .spec/issues/901-auto-decisions.md
  run_check "$want" "仕様レビュー: 「$line」は $([ "$want" = 0 ] && echo 非該当 || echo 停止)" issue 901 spec 900
done <<'LOGS'
0|| 停止条件チェック | 該当なし |
0|| 停止条件チェック | 該当なし（S4 非該当: 全項目が判定可能） |
0|| 停止条件チェック | **なし**（条件を課すことで解消） |
0|- 該当した停止条件: **無し**（S1: 3 ファイル存在）
0|| 停止条件チェック | S4 を検討したが、具体化により判定可能となるため停止しない |
1|| 停止条件チェック | S2（成功条件が測れない） |
1|| 停止条件チェック | 要確認 |
1|停止条件: S7（goal の書き換えを含む）
LOGS
# ★ このリポジトリの実際の判断ログ（.spec/issues/*-auto-decisions.md）を全部読ませる。
#   S1〜S8 の判定を書く前の 2 本（#75・#100。停止条件の行そのものが無い）だけが止まる
for f in "$REPO_ROOT"/.spec/issues/*-auto-decisions.md; do
  n="$(basename "$f")"; n="${n%%-*}"
  rm -f .spec/issues/*.md; cp "$f" .spec/issues/; printf '# Issue #%s: x\n' "$n" > ".spec/issues/$n-x.md"
  case "$n" in 75|100) want=1;; *) want=0;; esac
  run_check "$want" "仕様レビュー: 実際の判断ログ #$n を $([ "$want" = 0 ] && echo 通す || echo 止める)" issue "$n" spec 900
done
rm -f .spec/issues/*.md; printf '# Issue #901: x\n' > .spec/issues/901-x.md

# ── 前提の受け渡し（auto-reviewer と仕様整合の起動文）──
make_gh_stub '800:epic:OPEN:epic:parent=0
900:task:OPEN:t:parent=800
901:spec:OPEN:s:parent=900
'
rm -f .spec/issues/901-*.md
out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/task-run.sh" 900 2>&1)"
if has "$out" "auto-reviewer" && has "$out" "bash scripts/read-premises.sh 900 の出力を原文で貼る"; then
  ok "前提の受け渡し: auto-reviewer の起動の案内に read-premises.sh <TASK> がある"
else ng "前提の受け渡し: auto-reviewer の案内に read-premises.sh が無い"; fi
# ── 仕様整合と Closes（マージ直前。issue-finish.sh を通す）──
git checkout -q -B feature/900-i901
git commit -q --allow-empty -m "x

Refs #901"
echo y > y.txt; git add y.txt; git commit -qm "y

Refs #901"
CONF_OK='## /review 結果

| x | ok |

## 仕様整合

- goal 書き換え: なし
- positive control: 砂場で検出できた
- matched-engineering: 揃えた
- 格付け: verified-negative'
fin() {  # fin <種類>  issue-finish.sh の段 2 まで（落ちる場合だけ使う）
  out="$(PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
}
pr() { printf '%s\n' "$1" > "$SANDBOX/pr_body.txt"; }
rcheck() { local want="$1" what="$2"; shift 2; local o r; o="$(PATH="$SANDBOX/bin:$PATH" bash "$CHECK" "$@" 2>&1)"; r=$?
  if [ "$r" -eq "$want" ]; then ok "$what"; else ng "$what（期待 $want、実際 $r）"; printf '%s\n' "$o" | grep FAILED | sed 's/^/        /'; fi; }
pr "$CONF_OK"
rcheck 0 "仕様整合: そろえば merge の検査が通る（experiment）" merge 901 experiment 900
pr "${CONF_OK/- 格付け: verified-negative/- 格付け: unverified-negative}"
rcheck 1 "仕様整合: experiment の格付けが unverified-negative なら止まる" merge 901 experiment 900
pr "${CONF_OK/- 格付け: verified-negative/- 格付け: **unverified-negative**}"
rcheck 1 "仕様整合: 装飾つきの格付け **unverified-negative** でも止まる" merge 901 experiment 900
pr "${CONF_OK/- goal 書き換え: なし/- **goal 書き換え**: なし}"
rcheck 0 "仕様整合: 装飾つきの **goal 書き換え**: なし を読む" merge 901 experiment 900
pr "${CONF_OK/- 格付け: verified-negative/- 格付け: unverified-negative}"
make_gh_stub '800:epic:OPEN:epic:parent=0
900:task:OPEN:t:parent=800
901:experiment:OPEN:e:parent=900
'
fin; stop3 "仕様整合: unverified-negative の停止に 3 点がある（issue-finish.sh）" "$rc" "$out" "triage していない negative" "- 格付け: verified-negative" "bash scripts/flow/issue-finish.sh 901 900"
if has "$out" "bash scripts/read-premises.sh 900 の出力を原文で渡す" && has "$out" "verification"; then
  ok "前提の受け渡し: 仕様整合の起動の案内（マージ直前の停止）に read-premises.sh <TASK> がある"
else ng "前提の受け渡し: 仕様整合の案内に read-premises.sh が無い"; fi
if ! has "$out" "サブエージェントごとに 1 行ずつ判定を書く"; then ok "案内は落ちた項目の分だけ（仕様整合だけ落ちたら /review の案内を出さない）"
else ng "仕様整合だけ落ちたのに /review の案内も出している"; fi
pr "${CONF_OK/'## /review 結果'/'## 変更概要'}"
fin; stop3 "/review 結果が無いと書く行つきで止まる" "$rc" "$out" "'/review 結果' の見出しが無い" "## /review 結果" "bash scripts/flow/issue-finish.sh 901 900"
if has "$out" "サブエージェントごとに 1 行ずつ判定を書く" && ! has "$out" "read-premises.sh 900 の出力を原文で渡す"; then
  ok "★ 案内は落ちた項目の分だけ（/review だけ落ちたら仕様整合の起動の案内を出さない）"
else ng "/review だけ落ちたときの案内が違う（/review の案内が無いか、仕様整合の案内も出ている）"; fi
if [ "$(printf '%s\n' "$out" | grep -c '^  ok   ' || true)" -eq 0 ]; then ok "落ちたときは検査の出力を丸ごと出さない（FAILED の行だけを 1 回）"
else ng "落ちたのに検査の ok の行まで出している（2 回出している）"; fi
pr "${CONF_OK/- matched-engineering: 揃えた/}"
fin; stop3 "仕様整合: experiment で matched-engineering の行が無いと止まる" "$rc" "$out" "「matched-engineering:」の行が無い" "- matched-engineering:" "bash scripts/flow/issue-finish.sh 901 900"
pr "${CONF_OK/- goal 書き換え: なし/- goal 書き換え: あり}"
fin; stop3 "仕様整合: goal 書き換え: なし の行が無いと止まる" "$rc" "$out" "「goal 書き換え: なし」の行が無い" "- goal 書き換え: なし" "bash scripts/flow/issue-finish.sh 901 900"
pr "$CONF_OK
- ❌ 仕様の 3 節が未実装"
fin; stop3 "仕様整合: ❌ の項目があると止まる" "$rc" "$out" "❌ の項目がある" "（直してから" "bash scripts/flow/issue-finish.sh 901 900"
pr '## /review 結果

| x | ok |'
fin; stop3 "仕様整合: 節が無いと止まる" "$rc" "$out" "「## 仕様整合」節が無いか空" "## 仕様整合" "bash scripts/flow/issue-finish.sh 901 900"
pr '## /review 結果

| x | ok |

## 仕様整合

- goal 書き換え: なし'
rcheck 0 "仕様整合: feature なら 3 行（positive control 等）を求めない" merge 901 feature 900
rcheck 1 "仕様整合: validation なら 3 行を求める" merge 901 validation 900
pr "$CONF_OK"
git commit -q --allow-empty -m "z

Closes #901"
fin; stop3 "Closes: Closes #N のコミットがあると直し方つきで止まる" "$rc" "$out" "閉じるキーワード（Closes/Fixes/Resolves #901）を持つ" "Refs #901" "bash scripts/flow/issue-finish.sh 901 900"
if has "$out" "git commit --amend"; then ok "Closes: 直し方（amend / rebase）を出す"; else ng "Closes: 直し方を出していない"; fi
git reset -q --hard HEAD~1
git commit -q --allow-empty -m "z

Fixes #901"
rcheck 1 "Closes: Fixes #N のコミットも止める" merge 901 experiment 900
git reset -q --hard HEAD~1
pr "$CONF_OK

Closes #901"
fin; stop3 "Closes: PR 本文の Closes #N も止める" "$rc" "$out" "PR 本文が閉じるキーワード" "Refs #901" "bash scripts/flow/issue-finish.sh 901 900"
pr "$CONF_OK"
rcheck 0 "Closes: Refs だけなら通る" merge 901 experiment 900

# ★ git・gh の失敗を「見つからない」と読まない（閉じるキーワード・epic の数え上げ）
mkdir -p "$SANDBOX/gitfail"
# shellcheck disable=SC2016  # 偽 git の中身なので展開させない
printf '#!/usr/bin/env bash\ncase " $* " in *"$GIT_FAIL_ON"*) echo "git: boom" >&2; exit 128;; esac\nexec %q "$@"\n' \
  "$(command -v git)" > "$SANDBOX/gitfail/git"; chmod +x "$SANDBOX/gitfail/git"
fcheck() {  # fcheck <説明> <出力に要る語> <環境 NAME=VAL> <check-discipline の引数...>
  local what="$1" want="$2" envv="$3"; shift 3; local o r
  o="$(env "$envv" PATH="$SANDBOX/gitfail:$SANDBOX/bin:$PATH" bash "$CHECK" "$@" 2>&1)"; r=$?
  if [ "$r" -eq 1 ] && has "$o" "$want"; then ok "$what"; else ng "$what（rc=$r）"; printf '%s\n' "$o" | grep FAILED | sed 's/^/        /'; fi
}
fcheck "★ Closes: コミットの git log が失敗したら FAIL（キーワードが無いと読まない）" \
  "Closes: git log" GIT_FAIL_ON=--regexp-ignore-case merge 901 experiment 900
fcheck "★ Closes: PR の gh pr view が失敗したら FAIL（キーワードが無いと読まない）" \
  "PR 本文の閉じるキーワード: gh pr view が失敗した" GH_PR_VIEW_FAIL=1 merge 901 experiment 900
fcheck "★ epic: git log が失敗したら FAIL（0 件と読まない）" \
  "が失敗した（0 件と読まない）" GIT_FAIL_ON=--since= epic 800

# ★ 停止の記録を書けなくても、止まった理由（3 点）は先に出ている
pr "${CONF_OK/- goal 書き換え: なし/- goal 書き換え: あり}"
out="$(GH_COMMENT_FAIL=1 PATH="$SANDBOX/bin:$PATH" bash "$REPO_ROOT/scripts/flow/issue-finish.sh" 901 900 2>&1)"; rc=$?
stop3 "★ 停止の記録の投稿が落ちても 3 点を出す" "$rc" "$out" "「goal 書き換え: なし」の行が無い" "- goal 書き換え: なし" "bash scripts/flow/issue-finish.sh 901 900"
if has "$out" "警告: #900 への停止の記録を書けなかった"; then ok "→ 記録を書けなかったことを警告として出す"
else ng "記録を書けなかったことを出していない"; fi
pr "$CONF_OK"

cd "$REPO_ROOT" || exit 1
echo
printf '成立 %d / 不成立 %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
