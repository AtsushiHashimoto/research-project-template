#!/usr/bin/env bash
#
# scripts/flow/commit.sh の自己検証。
#
# ★ **検査が「落ちること」を、項目ごとに単独で確かめる。**
#   存在だけを見る検査は恒真になり、規律を完璧に守っても落ちる検査は恒偽になる。**両方を見る。**
#
# scripts/commit-merge.sh（削除済み）の回帰テストの性質もここに移した:
#   未コミット・未 push・一度も push していない・detached HEAD・存在しない worktree で
#   gh pr merge を呼ばずに止まる / lock した worktree・空白を含むパスでも後片付けまで完走する
#
# 実行:  ./tests/test_commit_flow.sh
# 終了:  0 全て成立 / 1 いずれか不成立
#
# ★ **砂場に scripts/ をコピーして、そのコピーを実行する**。
#   REPO_ROOT は lib.sh の 2 つ上なので砂場を指し、$QUALITY / $CHECK が砂場側の偽物になる。
#
# ── 偽 gh の応答表 ──────────────────────────────────────────────
#   gh repo view                  → x/y
#   gh issue view N --json labels → ラベル列 / state → 状態 / parent → 親番号
#   gh pr list --head V --state S → $GH_PR（既定 77）。**V が $GH_PR_HEAD と一致し、
#                                   S が $GH_PR_STATE（既定 open）と一致したときだけ**
#   gh pr view --json body        → `## /review 結果` 付き本文
#   gh pr merge N --squash        → $SB/merge_rc（既定 0）。呼ばれたことを $SB/calls.log に記録
#   gh api …/sub_issues           → 子番号（state を再現）
#
# ★ `| grep -q` / `| head ` を使わない（pipefail 下の SIGPIPE）。`grep -c` と [[ =~ ]] を使う。

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

code_of() { grep -vE '^[[:space:]]*#' "$1"; }
count_in_code() {
  local body; body="$(code_of "$1")"
  printf '%s' "$body" | grep -cE -e "$2" || true
}

SANDBOX="$(mktemp -d)" || { echo "mktemp -d が失敗した" >&2; exit 1; }
[ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] || { echo "砂場を作れない" >&2; exit 1; }
export SB="$SANDBOX"
export FAKE_GH="$REPO_ROOT/tests/lib/fake_gh.py" FAKE_GH_DIR="$SANDBOX/gh" FAKE_GH_ROWS="$SANDBOX/issues.txt"
trap 'rm -rf "${SANDBOX:?}"' EXIT
mkdir -p "${SANDBOX:?}/bin"

echo "=== flow/commit.sh の自己検証 ==="

# ══════════════════════════════════════════════════════════════════
# 静的な性質
# ══════════════════════════════════════════════════════════════════
echo "--- 静的な性質 ---"

n="$(wc -l <"$FLOW/commit.sh")"
if [ "$n" -le 300 ]; then ok "commit.sh は $n 行（上限 300）"
else ng "commit.sh は $n 行で上限 300 を超える"; fi

if [ "$(count_in_code "$FLOW/commit.sh" '\|[[:space:]]*(grep -q|head )')" -gt 0 ]; then  # pipefail-grep-q:allow 検出対象の綴りそのもの
  ng "commit.sh に pipefail の禁止形がある"
else ok "commit.sh に pipefail の禁止形が無い"; fi

for s in commit commit-only commit-push commit-merge; do
  f="$REPO_ROOT/.claude/skills/$s/SKILL.md"
  n="$(wc -l <"$f")"
  if [ "$n" -le 50 ]; then ok "$s/SKILL.md は $n 行（上限 50）"
  else ng "$s/SKILL.md は $n 行で上限 50 を超える"; fi
  if [ "$(grep -cE '^\s*(gh |git |\[ |bash scripts/check-discipline)' "$f" || true)" -gt 0 ]; then
    ng "$s/SKILL.md に判定・手順の bash が残っている"
  else ok "$s/SKILL.md に判定の bash が無い"; fi
  if [ "$(grep -cE '^description:' "$f" || true)" -gt 0 ]; then
    ok "$s/SKILL.md に frontmatter の description がある"
  else ng "$s/SKILL.md に description が無い"; fi
done

if [ -f "$REPO_ROOT/scripts/commit-merge.sh" ]; then
  ng "scripts/commit-merge.sh がまだ存在する（取り込んで削除したはず）"
else ok "scripts/commit-merge.sh が存在しない（flow/commit.sh に取り込んだ）"; fi

# ★ 対象は scripts/flow/（.spec/ と docs/ は過去の記録なので数えない）
left=0
for f in "$FLOW"/*.sh; do
  [ "$(count_in_code "$f" 'scripts/commit-merge\.sh')" -eq 0 ] && continue
  left=$((left + 1)); ng "$(basename "$f") が scripts/commit-merge.sh を指したまま"
done
if [ "$left" -eq 0 ]; then ok "scripts/flow/*.sh に scripts/commit-merge.sh の参照が無い"; fi

if [ "$(count_in_code "$FLOW/issue-finish.sh" 'flow/commit\.sh')" -gt 0 ]; then
  ok "issue-finish.sh の MERGE_CMD が flow/commit.sh を指す"
else ng "issue-finish.sh が flow/commit.sh を指していない"; fi

# ★ FLOW_FILES はスキルのディレクトリ .claude/skills/commit-merge/ を正当に挙げるので、
#   消したスクリプトとテストの名前だけを数える
if [ "$(count_in_code "$REPO_ROOT/scripts/quality-check.sh" 'scripts/commit-merge\.sh|test_commit_merge')" -eq 0 ]; then
  ok "quality-check.sh に commit-merge の検査ブロックが残っていない"
else ng "quality-check.sh が削除した commit-merge を指したまま"; fi

# ★ stage は名指し（git add -A / git add . を commit.sh / quick.sh のコードに書かない）
for f in commit.sh quick.sh; do
  if [ "$(count_in_code "$FLOW/$f" 'git add (-A|--all|\.)([[:space:]]|$)')" -eq 0 ]; then
    ok "$f は git add -A / git add . を使わない"
  else ng "$f が git add -A / git add . を使っている（名指しで stage する）"; fi
done

# ★ 足切りの拡張は**動的に**確かめる。
#   grep で「set -e という語があるか」を見るだけだと、同ファイルが違反の雛形を
#   書き出す行（`echo 'set -euo pipefail'`）にも当たって**恒真**になる
#   （足切り本体を削除しても緑のままだった。実測）。
check_filter() {  # check_filter <期待コード> <説明> <違反ファイルの 1 行目>
  local want="$1" what="$2" first="$3" R="$SANDBOX/filter" out rc
  rm -rf "$R"; mkdir -p "$R/tests" "$R/scripts"
  cp "$REPO_ROOT/tests/test_pipefail_grep_q.sh" "$R/tests/"
  # shellcheck disable=SC2016  # 違反ファイルの**中身**なので展開させない
  { printf '#!/usr/bin/env bash\n%s\n' "$first"
    printf 'MAIN=$(git worktree list | head -1 | awk "{print \\$1}")\n'  # pipefail-grep-q:allow 違反の雛形そのもの
    printf 'echo "$MAIN"\n'; } > "$R/scripts/violator.sh"
  ( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t \
    && git add -A && git commit -qm x ) >/dev/null 2>&1
  out="$(cd "$R" && bash tests/test_pipefail_grep_q.sh 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -3 | sed 's/^/        /'; fi
}
check_filter 1 "★ set -e だけのファイルの禁止形を検出する（足切りの拡張が効いている）" "set -e"
check_filter 0 "★ set -e が無ければ対象外のまま（拡張が恒真でないことの確認）" "# set は無い"

# ══════════════════════════════════════════════════════════════════
# 砂場
# ══════════════════════════════════════════════════════════════════
make_gh() {
  cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# ★ §4 のゲートが使う呼び出し（本文・コメント・コメントの追加）は
#   issue ごとの状態を持つ tests/lib/fake_gh.py に回す
case "$*" in "issue view "*" --json body,comments,createdAt"*) exec python3 -B "$FAKE_GH" "$@";; esac
if [ "$1 $2" = "issue comment" ]; then python3 -B "$FAKE_GH" "$@" || exit 1; fi
f="$SB/issues.txt"
row() { grep -E "^$1:" "$f" || true; }
case "$1 $2" in
  "repo view") echo "x/y"; exit 0;;
esac
if [ "$1" = issue ] && { [ "$2" = comment ] || [ "$2" = close ]; }; then
  printf '%s %s\n' "$2" "$3" >> "$SB/gh.log"; exit 0
fi
if [ "$1" = issue ] && [ "$2" = view ]; then
  r="$(row "$3")"; [ -n "$r" ] || { echo "not found" >&2; exit 1; }
  IFS=: read -r _ labels state title parent <<< "$r"
  case "$*" in
    *labels*) echo "$labels";; *state*) echo "$state";;
    *parent*) echo "${parent#parent=}";; *) echo "$title";;
  esac
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = list ]; then
  head=""; state="open"
  while [ $# -gt 0 ]; do
    case "$1" in --head) head="${2:-}";; --state) state="${2:-}";; esac; shift
  done
  if [ "$state" = "${GH_PR_STATE:-open}" ] && [ "$head" = "${GH_PR_HEAD:-__unset__}" ]; then
    printf '%s\n' ${GH_PR:-77}
  fi
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  if [ -n "${GH_PR_NO_REVIEW:-}" ]; then echo "## 変更概要"; else
    echo "## /review 結果"; echo ""; echo "| x | ok |"; fi
  printf '%s\n' "${GH_PR_CONFORM-$'## 仕様整合\n\n- goal 書き換え: なし\n- positive control: 砂場で検出できた\n- matched-engineering: 揃えた\n- 格付け: verified-negative'}"
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = merge ]; then
  printf 'gh pr merge %s\n' "$3" >> "$SB/calls.log"
  # ★ GitHub の "Automatically delete head branches" の再現。
  #   **マージの中で**消えるのが実際の挙動で、マージ前に消すのは起こらない状況
  if [ -n "${DELETE_REMOTE:-}" ]; then
    git -C "$SB/repo" push -q origin --delete "${GH_PR_HEAD:-}" 2>/dev/null
  fi
  # ★ マージ**後**に既定ブランチが引けなくなる状況を作る（これを再現できる唯一の位置）
  if [ -n "${BREAK_BASE:-}" ]; then
    git -C "$SB/repo" update-ref -d refs/heads/main 2>/dev/null
    git -C "$SB/repo" update-ref -d refs/remotes/origin/main 2>/dev/null
  fi
  exit "$(cat "$SB/merge_rc" 2>/dev/null || echo 0)"
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
      done < "$f"; exit 0;;
    *) echo "999888"; exit 0;;
  esac
fi
exit 0
STUB
  chmod +x "$SANDBOX/bin/gh"
}

FIXTURE='900:task:OPEN:task:parent=800
901:spec:OPEN:spec段:parent=900
902:feature:OPEN:feature段:parent=900
903:docs:CLOSED:閉じた issue:parent=900
'

setup_sandbox() {
  local R="$SANDBOX/repo"
  rm -rf "$R"; mkdir -p "$R/scripts/flow"
  cp "$FLOW"/*.sh "$R/scripts/flow/"
  cp "$REPO_ROOT/scripts/check-discipline.sh" "$REPO_ROOT/scripts/check-discipline-predicates.sh" "$REPO_ROOT/scripts/check-discipline-gates.py" "$REPO_ROOT/scripts/check_discipline_md.py" \
     "$REPO_ROOT/scripts/worktree-relative.sh" "$R/scripts/"
  # 偽の品質チェック（本物は readonly で差し替え不可なので、コピーで置き換える）
  cat > "$R/scripts/quality-check.sh" <<'SH'
#!/usr/bin/env bash
printf 'quality scope=%s base=%s\n' "${QUALITY_SCOPE:-}" "${QUALITY_BASE_BRANCH:-（無し）}" >> "$SB/calls.log"
exit "$(cat "$SB/quality_rc" 2>/dev/null || echo 0)"
SH
  chmod +x "$R/scripts"/*.sh "$R/scripts/flow"/*.sh
  # ★ 本物の remote を置く（`git pull --ff-only` が成立しないと、正常経路が exit 10 になる）
  rm -rf "$SANDBOX/remote.git"; git init -q --bare "$SANDBOX/remote.git"
  ( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t \
    && echo base > a.txt && git add -A && git commit -qm base \
    && git remote add origin "$SANDBOX/remote.git" \
    && git push -q origin main \
    && git checkout -q -b "spec/900-i901" ) >/dev/null 2>&1
  rm -f "$SANDBOX/calls.log" "$SANDBOX/gh.log" "$SANDBOX/quality_rc" "$SANDBOX/merge_rc"
  printf '%s' "$FIXTURE" > "$SANDBOX/issues.txt"
  export GH_PR_HEAD="spec/900-i901"
}

# run <期待コード> <説明> <引数...>   砂場の commit.sh を砂場の中で実行する
run() {
  local want="$1" what="$2"; shift 2
  local out rc
  out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" \
         bash "$SANDBOX/repo/scripts/flow/commit.sh" "$@" 2>&1)"; rc=$?
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
# only / push
# ══════════════════════════════════════════════════════════════════
echo "--- only / push ---"
run 1 "サブコマンドが無いと落ちる"
run 1 "未知のサブコマンドで落ちる" nonsense
run 1 "--issue が無いと落ちる（ブランチ名から推測しない）" only --message x
run 1 "--message が無いと落ちる（文言を捏造しない）"       only --issue 901
run 1 "--issue が数値でないと落ちる"                      only --issue abc --message x
run 1 "closed な issue を渡すと落ちる"                    only --issue 903 --message x
run 1 "未知のオプションで落ちる"                          only --issue 901 --message x --lable y

( cd "$SANDBOX/repo" && git checkout -q main )
run 1 "main に居ると落ちる" only --issue 901 --message x
( cd "$SANDBOX/repo" && git checkout -q "spec/900-i901" )

run 1 "作業ツリーに変更が無いと落ちる（空コミットを作らない）" only --issue 901 --message x

echo new > "$SANDBOX/repo/b.txt"
# ★ stage していない変更だけなら止まる（git add -A で拾わない。名指しを促す）
run 1 "★ 未追跡ファイルだけ（stage なし）なら止まる" only --issue 901 --message "テストのコミット"
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'git add <ファイル名>' || true)" -gt 0 ] \
   && [ "$(printf '%s' "$LAST_OUT" | grep -cF 'b.txt' || true)" -gt 0 ]; then
  ok "→ 一覧（b.txt）と git add <ファイル名> の例を出す"
else ng "停止の出力に一覧か git add の例が無い: $(printf '%s' "$LAST_OUT" | tail -3)"; fi
if [ -n "$(git -C "$SANDBOX/repo" diff --cached --name-only)" ]; then
  ng "止まったのに index に何か stage されている"; else ok "→ index に触っていない"; fi
echo junk > "$SANDBOX/repo/junk.txt"
git -C "$SANDBOX/repo" add b.txt
run 0 "stage 済みならコミットする" only --issue 901 --message "テストのコミット"
if [ "$(git -C "$SANDBOX/repo" show --name-only --format= HEAD | grep -cx 'junk.txt' || true)" -eq 0 ] \
   && [ "$(git -C "$SANDBOX/repo" show --name-only --format= HEAD | grep -cx 'b.txt' || true)" -eq 1 ]; then
  ok "★ stage したもの（b.txt）だけが入り、未 stage の junk.txt は入らない"
else ng "コミットの中身が stage と違う: $(git -C "$SANDBOX/repo" show --name-only --format= HEAD | tr '\n' ' ')"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'stage しなかった変更が残っている' || true)" -gt 0 ]; then
  ok "→ 残した変更を黙らない"; else ng "未 stage の残りを報告していない"; fi
rm -f "$SANDBOX/repo/junk.txt"
msg="$(git -C "$SANDBOX/repo" log -1 --format=%B)"
if [ "$(printf '%s' "$msg" | grep -cF 'Refs #901' || true)" -gt 0 ]; then
  ok "★ Refs #901（--issue の値）が入る。ブランチ spec/900-i901 の 900 にならない"
else ng "Refs の番号が --issue の値でない: $(printf '%s' "$msg" | tail -3)"; fi
if [ "$(printf '%s' "$msg" | grep -cxF 'Co-Authored-By: Claude <noreply@anthropic.com>' || true)" -gt 0 ]; then
  ok "共著者の行（lib.sh の定数）が入る"; else ng "共著者の行が無い: $(printf '%s' "$msg" | tail -1)"; fi

# push（砂場には本物の bare remote があるので成功する）
echo more > "$SANDBOX/repo/c.txt"
git -C "$SANDBOX/repo" add c.txt
run 0 "変更があれば commit してから push する" push --issue 901 --message "push の試験"
if [ -z "$(git -C "$SANDBOX/repo" status --porcelain)" ]; then
  ok "★ push の前にコミットを済ませている（stage 済み → commit の分岐）"
else ng "コミットしていない"; fi
# ★ 変更が無くても未 push があれば push だけ行う
( cd "$SANDBOX/repo" && git commit -q --allow-empty -m "未 push のコミット

Refs #901" ) >/dev/null
run 0 "★ 変更は無いが未 push があれば push だけ行う" push --issue 901 --message "使われないはず"
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '未 push のコミットがあるので push だけ' || true)" -gt 0 ]; then
  ok "その旨を出力する"; else ng "push だけの分岐に入っていない"; fi
run 1 "★ 変更も未 push も無ければ落ちる" push --issue 901 --message "使われないはず"

# ══════════════════════════════════════════════════════════════════
# merge
# ══════════════════════════════════════════════════════════════════
echo "--- merge ---"
prepare_merge() {
  setup_sandbox
  printf 'x\n' > "$SANDBOX/repo/d.txt"
  # ★ **push まで行う**。`commit.sh merge` は「PR がある＝origin に枝がある」を
  #   前提に、未 push のコミットが squash に載らないことを検査するようになった
  ( cd "$SANDBOX/repo" && git add -A && git commit -qm "作業

Refs #901" && git push -q origin "spec/900-i901" ) >/dev/null 2>&1
  # ★ push の失敗を黙らせない。黙ると merge 系がまとめて原因不明の赤になる
  git -C "$SANDBOX/repo" ls-remote --exit-code --heads origin "spec/900-i901" >/dev/null 2>&1 \
    || ng "（前提）prepare_merge が origin へ push できていない"
}

prepare_merge
run 1 "引数なしで落ちる" merge
run 1 "issue 番号が数値でないと落ちる" merge abc
run 1 "引数が多いと落ちる" merge 901 900 /tmp/x /tmp/y

# ★ check merge が落ちる側（PR が無い / Refs が無い）では gh pr merge を呼ばない
prepare_merge
GH_PR_HEAD="other" run 1 "PR が無いと落ちる" merge 901 900
if has_call "gh pr merge"; then ng "PR が無いのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi

prepare_merge
( cd "$SANDBOX/repo" && git commit -q --amend -m "参照なし" ) >/dev/null
run 1 "Refs #N のコミットが無いと落ちる" merge 901 900
if has_call "gh pr merge"; then ng "Refs が無いのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi

# ★ 品質チェックが落ちる側
prepare_merge; echo 1 > "$SANDBOX/quality_rc"
run 1 "品質チェックが落ちると落ちる" merge 901 900
if has_call "gh pr merge"; then ng "品質チェック失敗でもマージしている"; else ok "→ gh pr merge を呼ばない"; fi
rm -f "$SANDBOX/quality_rc"

# ★ check merge は品質チェックより先（規律違反に品質チェックの時間を払わせない）
#   ★ 前提は「Refs #N のコミットが無い」で作る（PR 不在では check merge の 3 述語は通ってしまう）
prepare_merge
( cd "$SANDBOX/repo" && git commit -q --amend -m "参照なし" ) >/dev/null
rm -f "$SANDBOX/calls.log"
run 1 "（前提）Refs #N のコミットが無い状態" merge 901 900
if has_call "quality scope="; then
  ng "check merge が落ちる前に品質チェックを走らせている"
else ok "★ check merge が品質チェックより先"; fi

# ★ 未 push のコミットがあるとマージしない（squash は origin 側を畳むので、
#   ローカルにしか無いコミットは載らないまま worktree が --force 削除される）
prepare_merge
printf 'local only\n' > "$SANDBOX/repo/e.txt"
( cd "$SANDBOX/repo" && git add -A && git commit -qm "未 push

Refs #901" ) >/dev/null
run 1 "★ 未 push のコミットがあると落ちる（squash に載らないまま消えるのを防ぐ）" merge 901 900
if has_call "gh pr merge"; then ng "未 push があるのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'ローカルにしか無いコミット' || true)" -gt 0 ]; then
  ok "→ 落ちた理由が未 push である（他の検査に素通りしていない）"
else ng "未 push の検査を素通りしている: $(printf '%s' "$LAST_OUT" | tail -2)"; fi

# ★ origin に枝が無い場合も落ちる（「引けない」を 0 と読まない）
prepare_merge
( cd "$SANDBOX/repo" && git push -q origin --delete "spec/900-i901" ) >/dev/null 2>&1
run 1 "★ origin に枝が無いと落ちる（引けないを「差分なし」と読まない）" merge 901 900
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'origin に spec/900-i901 が無い' || true)" -gt 0 ]; then
  ok "→ 落ちた理由が origin の枝の不在である"
else ng "origin の枝の不在を素通りしている: $(printf '%s' "$LAST_OUT" | tail -2)"; fi

# ★ closed な issue では merge まで進めない（only/push と揃える）
prepare_merge
run 1 "closed な issue を渡すと merge も落ちる" merge 903 900
if has_call "gh pr merge"; then ng "closed な issue なのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi
# ★ **落ちた理由まで見る**。`Refs #903` のコミットが無いので
#   `check merge` でも 1 で落ちる。終了コードだけでは open 確認の有無を区別できない（恒真）
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'open でない' || true)" -gt 0 ]; then
  ok "★ 落ちた理由が open 確認である（check merge に素通りしていない）"
else ng "open 確認を素通りしている: $(printf '%s' "$LAST_OUT" | tail -2)"; fi

# ★ PR が 2 本以上
prepare_merge
GH_PR="77 78" run 1 "同じ head に open な PR が 2 本 → 落ちる（.[0] で選ばない）" merge 901 900

# ★ メインリポジトリのパスを worktree として渡す
prepare_merge
run 1 "メインリポジトリのパスを worktree として渡すと落ちる" merge 901 900 "$SANDBOX/repo"

# ★ 別ブランチの worktree を渡す（無関係な worktree を消させない）
prepare_merge
( cd "$SANDBOX/repo" && git worktree add -q "$SANDBOX/other-wt" -b "feature/777-x" ) >/dev/null 2>&1
run 1 "★ 別ブランチの worktree を渡すと落ちる（消す対象の取り違えを防ぐ）" merge 901 900 "$SANDBOX/other-wt"
if has_call "gh pr merge"; then ng "取り違えた worktree なのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi
git -C "$SANDBOX/repo" worktree remove --force "$SANDBOX/other-wt" 2>/dev/null

# ★ 全部揃っていればマージする
prepare_merge
run 0 "全部揃っていれば 0 で終わる" merge 901 900
if has_call "gh pr merge 77"; then ok "gh pr merge を PR 番号で呼ぶ"; else ng "gh pr merge を呼んでいない"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'worktree は指定されていないので残す' || true)" -gt 0 ]; then
  ok "worktree 無指定のとき「残す」と出力する（黙らない）"
else ng "「残す」の出力が無い"; fi

# ★ PR 本文に /review 結果 が無い（第 2 経路を塞ぐ主目的の条件）
prepare_merge
GH_PR_NO_REVIEW=1 run 1 "PR 本文に /review 結果 が無いと落ちる" merge 901 900
if has_call "gh pr merge"; then ng "レビュー結果なしでマージしている"; else ok "→ gh pr merge を呼ばない"; fi

# ★ マージ自体が失敗
prepare_merge; echo 1 > "$SANDBOX/merge_rc"
run 1 "gh pr merge が失敗したら落ちる（exit 1＝マージしていない）" merge 901 900
rm -f "$SANDBOX/merge_rc"

# ══════════════════════════════════════════════════════════════════
# 後片付け（worktree を渡す正常系。**最も破壊的な経路**）
# ══════════════════════════════════════════════════════════════════
echo "--- 後片付け（worktree を渡す） ---"
# run_in <ディレクトリ> <期待コード> <説明> <引数...>
run_in() {
  local dir="$1" want="$2" what="$3"; shift 3
  local out rc
  out="$(cd "$dir" && PATH="$SANDBOX/bin:$PATH" \
         bash "$SANDBOX/repo/scripts/flow/commit.sh" "$@" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/        /'; fi
}

WT="$SANDBOX/wt"
prepare_wt() {  # 砂場に「作業用 worktree」を作り、そこにコミットを積む（$WT。空白を含めてもよい）
  setup_sandbox
  # ★ 直前の試験が exit 10 で抜けると worktree が残る。消さないと `git worktree add` が
  #   失敗し、**親を消された古い worktree がそのまま使われて detached HEAD になる**
  rm -rf "${SANDBOX:?}/wt" "${SANDBOX:?}/w t"
  git -C "$SANDBOX/repo" worktree prune 2>/dev/null
  ( cd "$SANDBOX/repo" && git checkout -q main \
    && git branch -D "spec/900-i901" >/dev/null 2>&1
    git worktree add -q "$WT" -b "spec/900-i901" ) >/dev/null 2>&1
  # ★ `git worktree add` の失敗を黙らせない（黙ると「期待 10、実際 1」の原因不明の FAIL になる）
  [ "$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null)" = "spec/900-i901" ] \
    || ng "（前提）prepare_wt が worktree を作れていない"
  printf 'x\n' > "$WT/d.txt"
  ( cd "$WT" && git add d.txt && git commit -qm "作業

Refs #901" && git push -q origin "spec/900-i901" ) >/dev/null 2>&1
  git -C "$SANDBOX/repo" ls-remote --exit-code --heads origin "spec/900-i901" >/dev/null 2>&1 \
    || ng "（前提）prepare_wt が origin へ push できていない"
}

prepare_wt
run_in "$SANDBOX/wt" 0 "★ worktree を渡した正常系が 0 で終わる" merge 901 900 "$SANDBOX/wt"
if [ -d "$SANDBOX/wt" ]; then ng "worktree が消えていない"; else ok "★ worktree を削除した"; fi
if git -C "$SANDBOX/repo" rev-parse --verify --quiet "refs/heads/spec/900-i901" >/dev/null; then
  ng "ローカルブランチが残っている"; else ok "★ ローカルブランチを削除した"; fi
if git -C "$SANDBOX/repo" ls-remote --exit-code --heads origin "spec/900-i901" >/dev/null 2>&1; then
  ng "リモートブランチが残っている"; else ok "★ リモートブランチを削除した"; fi

# ★ lock した worktree も消せる（scripts/worktree-relative.sh add は作った worktree を lock する）
prepare_wt
git -C "$SANDBOX/repo" worktree lock "$SANDBOX/wt" >/dev/null 2>&1
run_in "$SANDBOX/wt" 0 "★ lock した worktree を渡しても 0 で終わる" merge 901 900 "$SANDBOX/wt"
if [ -d "$SANDBOX/wt" ]; then ng "lock した worktree が消えていない"; else ok "★ lock した worktree も unlock して削除した"; fi

# ★ パスに空白を含む worktree でも後片付けまで完走する
WT="$SANDBOX/w t"; prepare_wt
run_in "$WT" 0 "★ 空白を含むパスの worktree でも 0 で終わる" merge 901 900 "$WT"
if [ -d "$WT" ]; then ng "空白を含むパスの worktree が消えていない"; else ok "→ 削除した"; fi
WT="$SANDBOX/wt"

# ★ 未追跡ファイルが残っていれば止まる（--force の削除で失われるため）
prepare_wt; echo x > "$WT/d.csv"
run_in "$WT" 1 "★ 未追跡ファイルがあれば止まる" merge 901 900 "$WT"
if has_call "gh pr merge"; then ng "未追跡ファイルがあるのにマージしている"; else ok "→ gh pr merge を呼ばない"; fi
if [ -d "$WT" ]; then ok "→ worktree を残す"; else ng "未追跡ファイルごと worktree を消した"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'コミットしていない変更がある' || true)" -gt 0 ]; then
  ok "→ 落ちた理由が未コミットの変更である"; else ng "未コミットの検査を素通りしている"; fi

# ★ detached HEAD なら止まる
prepare_wt; git -C "$WT" checkout -q --detach
run_in "$WT" 1 "★ detached HEAD なら止まる" merge 901 900 "$WT"
if has_call "gh pr merge"; then ng "detached HEAD でマージしている"; else ok "→ gh pr merge を呼ばない"; fi

# ★ 存在しない worktree なら止まる
prepare_wt
run_in "$WT" 1 "★ 存在しない worktree を渡すと止まる" merge 901 900 "$SANDBOX/nonexistent"
if has_call "gh pr merge"; then ng "存在しない worktree でマージしている"; else ok "→ gh pr merge を呼ばない"; fi

# ★ 「もう無い」は失敗にしない（Automatically delete head branches が有効な環境）
#   ★ **マージの中で**消す。マージ前に消すと、いまは「origin に枝が無い」で
#     正しく落ちるので、この経路を踏めない
prepare_wt
DELETE_REMOTE=1 run_in "$SANDBOX/wt" 0 "★ リモートブランチが既に無くても 0 で終わる（「もう無い」を失敗にしない）" \
  merge 901 900 "$SANDBOX/wt"
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'リモートブランチは既に無い' || true)" -gt 0 ]; then
  ok "その旨を出力する"; else ng "「既に無い」の出力が無い"; fi

# ★ 既定ブランチの更新が失敗したら exit 10（マージは済んでいる）
prepare_wt
rm -rf "$SANDBOX/remote.git"        # pull が必ず落ちる状態にする
run_in "$SANDBOX/wt" 10 "★ 既定ブランチの更新が失敗したら exit 10（マージは済んでいる）" \
  merge 901 900 "$SANDBOX/wt"
if has_call "gh pr merge 77"; then ok "→ マージ自体は済んでいる（だから 1 ではなく 10）"
else ng "マージを呼んでいない"; fi

# ★ 既定ブランチを**解決できない**ときも exit 10（以前は die で exit 1 になり、
#   issue-finish.sh が「マージが失敗した」と嘘を書いて issue を open のまま残していた）
prepare_wt
( cd "$SANDBOX/repo" && git checkout -q --detach ) >/dev/null 2>&1
BREAK_BASE=1 run_in "$SANDBOX/wt" 10 "★ 既定ブランチを解決できないときも exit 10（die の 1 に戻らない）" \
  merge 901 900 "$SANDBOX/wt"
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '既定ブランチを解決できない' || true)" -gt 0 ]; then
  ok "→ 解決できない旨を出力する"; else ng "「既定ブランチを解決できない」の出力が無い"; fi
# ★ **マージは済んでいる**と明言しているか（この取り違えを防ぐのが目的）
if [ "$(printf '%s' "$LAST_OUT" | grep -cF 'マージは済んでいる' || true)" -gt 0 ]; then
  ok "★ 「マージは済んでいる」と出力する（マージし直させない）"
else ng "マージ済みであることを伝えていない"; fi
if has_call "gh pr merge 77"; then ok "→ マージ自体は済んでいる（だから 1 ではなく 10）"
else ng "マージを呼んでいない"; fi

# ══════════════════════════════════════════════════════════════════
# 送り手・受け手が同じ定数／同じ述語を読む
# ══════════════════════════════════════════════════════════════════
echo "--- 共有の定数・述語 ---"

if [ "$(count_in_code "$FLOW/lib.sh" 'readonly POST_MERGE_FAILED=')" -eq 1 ]; then
  ok "POST_MERGE_FAILED の定義は lib.sh に 1 つだけ"
else ng "POST_MERGE_FAILED の定義が lib.sh に無い（または重複している）"; fi
# ★ 検出の綴りは 1 箇所（下の positive control が同じ式を使う。写経すると片方だけ直る）
# shellcheck disable=SC2016  # 検出したい**綴りそのもの**なので展開させない
BARE10='(^|[[:space:]])(exit|=|!=|-eq|-ne)[[:space:]]*"?10"?([[:space:]]|\]|;|$)'
for f in commit.sh issue-finish.sh; do
  if [ "$(count_in_code "$FLOW/$f" "$BARE10")" -gt 0 ]; then
    ng "$f に裸の 10 が残っている（定数を読むこと）"
  else ok "$f は裸の 10 を書かない"; fi
done
# ★ 否定側だけだと「10 も定数も書かない」＝**参照を消しただけ**で緑になる。
#   送り手（commit.sh）は lib.sh:post_merge_fail 経由で抜け、受け手（issue-finish.sh）は
#   定数と比較する。**どちらも「共有の出口」を通っていること**を見る
if [ "$(count_in_code "$FLOW/commit.sh" 'post_merge_fail ')" -gt 0 ]; then
  ok "commit.sh はマージ後の失敗を post_merge_fail（lib.sh）から抜ける"
else ng "commit.sh が post_merge_fail を使っていない（終了コードが散る）"; fi
# shellcheck disable=SC2016  # 検出したい**綴りそのもの**なので展開させない
if [ "$(count_in_code "$FLOW/lib.sh" 'exit "\$POST_MERGE_FAILED"')" -eq 1 ]; then
  ok "その終了コードで抜ける場所は lib.sh の 1 箇所だけ"
else ng "POST_MERGE_FAILED で抜ける場所が lib.sh に 1 つでない"; fi
if [ "$(count_in_code "$FLOW/issue-finish.sh" 'POST_MERGE_FAILED')" -gt 0 ]; then
  ok "issue-finish.sh は \$POST_MERGE_FAILED を実際に読む"
else ng "issue-finish.sh が \$POST_MERGE_FAILED を一度も参照していない"; fi
# ★ **検出力の確認**。以前の式は `exit 10` も `-eq 10` も取りこぼしていた
probe="$SANDBOX/bare10.sh"
# shellcheck disable=SC2016  # 違反の**見本**なので展開させない
{ printf 'exit 10\n'; printf '[ "$rc" -eq 10 ]\n'; } > "$probe"
if [ "$(count_in_code "$probe" "$BARE10")" -eq 2 ]; then
  ok "★ 裸の 10 の検出式は exit 10 と -eq 10 の両方に当たる（恒真でない）"
else ng "検出式が守りたい綴りに当たらない（$(count_in_code "$probe" "$BARE10") / 期待 2）"; fi
# shellcheck disable=SC2016  # 違反しない綴りの**見本**なので展開させない
{ printf 'exit "$POST_MERGE_FAILED"\n'; printf 'x=100\n'; printf 'sleep 10s\n'; } > "$probe"
if [ "$(count_in_code "$probe" "$BARE10")" -eq 0 ]; then
  ok "★ 正しい綴り・無関係な 100/10s には当たらない（恒偽でない）"
else ng "検出式が誤検出する（$(count_in_code "$probe" "$BARE10") / 期待 0）"; fi
rm -f "$probe"

# ★ PR 解決の述語は lib.sh に 1 つ。両者がそれを呼ぶ（写経すると片方だけ直る）
if [ "$(count_in_code "$FLOW/lib.sh" '^open_pr_for\(\)')" -eq 1 ]; then
  ok "open_pr_for の定義は lib.sh に 1 つだけ"; else ng "open_pr_for が lib.sh に無い"; fi
# ★ 綴りの並びで見ると**行を折り返すだけで抜けられる**（実測）。
#   `--state open` の出現数が flow 全体で 1 なら、直叩きは存在し得ない
tot=0
for f in "$FLOW"/*.sh; do tot=$((tot + $(count_in_code "$f" '--state open'))); done
if [ "$tot" -eq 1 ] && [ "$(count_in_code "$FLOW/lib.sh" '--state open')" -eq 1 ]; then
  ok "open な PR の問い合わせは lib.sh:open_pr_for の 1 箇所だけ（flow 全体で $tot）"
else ng "open な PR の問い合わせが flow 全体で $tot 箇所ある（open_pr_for に畳むこと）"; fi
for f in commit.sh issue-finish.sh; do
  if [ "$(count_in_code "$FLOW/$f" 'open_pr_for ')" -gt 0 ]; then ok "$f は open_pr_for を呼ぶ"
  else ng "$f が open_pr_for を呼んでいない"; fi
done

# ★ 既定ブランチは main 固定（git-workflow.md）。origin/HEAD から検出しない。名前は lib.sh の定数 1 つ
# ★ lib.sh だけ数えると、**写経が lib.sh の外に出た瞬間に網が外れる**（実測）
tot=0; def=0
for f in "$FLOW"/*.sh; do
  tot=$((tot + $(count_in_code "$f" 'origin/HEAD|symbolic-ref .*refs/remotes')))
  def=$((def + $(count_in_code "$f" 'DEFAULT_BRANCH=')))
done
if [ "$tot" -eq 0 ]; then ok "flow/*.sh は origin/HEAD から既定ブランチを検出しない"
else ng "flow/*.sh に origin/HEAD の検出が $tot 箇所ある（main 固定にすること）"; fi
if [ "$def" -eq 1 ] && [ "$(count_in_code "$FLOW/lib.sh" '^readonly DEFAULT_BRANCH=main$')" -eq 1 ]; then
  ok "既定ブランチの名前は lib.sh の readonly DEFAULT_BRANCH=main の 1 箇所だけ"
else ng "既定ブランチの定義が lib.sh に 1 つでない（flow 全体で $def）"; fi
# 共著者の行も lib.sh の定数 1 つ（環境変数で変えない）
tot=0
for f in "$FLOW"/*.sh; do tot=$((tot + $(count_in_code "$f" 'Co-Authored-By'))); done
if [ "$tot" -eq 1 ] && [ "$(count_in_code "$FLOW/lib.sh" '^readonly CO_AUTHOR="Co-Authored-By: Claude <noreply@anthropic.com>"$')" -eq 1 ]; then
  ok "共著者の行は lib.sh の readonly CO_AUTHOR の 1 箇所だけ"
else ng "共著者の行が flow 全体で $tot 箇所（lib.sh の定数 1 つにすること）"; fi
# 削除は scripts/worktree-relative.sh remove だけを通す
tot=0
for f in "$FLOW"/*.sh; do tot=$((tot + $(count_in_code "$f" 'git (-C [^ ]+ )?worktree (remove|unlock)'))); done
if [ "$tot" -eq 0 ]; then ok "flow/*.sh は git worktree remove / unlock を直に呼ばない"
else ng "flow/*.sh が git worktree remove / unlock を $tot 箇所で直に呼ぶ（worktree-relative.sh remove を通す）"; fi

# ★ 保護ブランチの綴りを裸で書かない（PROTECTED_BRANCHES を読む）
bare=0
for f in "$FLOW"/*.sh; do
  # ★ `in main|master)` という 1 通りの並びを探すと `master|main)` で抜けられる（/review で実測）。
  #   単一情報源は check-discipline-predicates.sh（$FLOW の外）なので、綴りの有無で見てよい
  [ "$(count_in_code "$f" 'master')" -eq 0 ] && continue
  bare=$((bare + 1)); ng "$(basename "$f") が保護ブランチ名を裸で書いている（\$PROTECTED_BRANCHES を読むこと）"
done
if [ "$bare" -eq 0 ]; then ok "flow/*.sh は保護ブランチを \$PROTECTED_BRANCHES で読む"; fi

# ★ `case` のパターンに変数を置かない（`|` が選択肢として解釈されず、
#   `main|master` という 1 つの文字列と比較され、**保護ブランチの判定が丸ごと無効になる**）
bad=0
for f in "$FLOW"/*.sh; do
  # shellcheck disable=SC2016  # 検出したい**綴りそのもの**なので展開させない
  [ "$(count_in_code "$f" 'case .* in \$(PROTECTED_BRANCHES|BRANCH_TYPES)')" -eq 0 ] && continue
  bad=$((bad + 1)); ng "$(basename "$f") が case のパターンに変数を置いている（| が効かない）"
done
if [ "$bad" -eq 0 ]; then ok "case のパターンに \$PROTECTED_BRANCHES 等を置いていない" ; fi

# ★ issue-finish.sh の順序は **tests/test_issue_flow.sh で動的に**見る。
#   行番号 grep は `if ! check merge …; then` のような挙動を変えない書き換えで落ちる（恒偽）。

# ══════════════════════════════════════════════════════════════════
# 品質チェックの記録
# ══════════════════════════════════════════════════════════════════
echo "--- 品質チェックの記録 ---"
q() {  # q <期待コード> <説明> <kind>
  local want="$1" what="$2" kind="$3"
  local out rc
  out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" bash -c \
        '. scripts/flow/lib.sh; run_quality "$1"' _ "$kind" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -3 | sed 's/^/        /'; fi
}
rec_file() { printf '%s/flow-quality-passed' "$(git -C "$SANDBOX/repo" rev-parse --absolute-git-dir)"; }

setup_sandbox
rm -f "$SANDBOX/calls.log"
q 0 "記録が無ければ走らせる" feature
if has_call "quality scope=all"; then ok "→ 実際に走った"; else ng "走っていない"; fi

rm -f "$SANDBOX/calls.log"
q 0 "2 回目は省く（記録が一致）" feature
if has_call "quality scope="; then ng "省いていない"; else ok "→ 走らせていない"; fi
if [ "$(printf '%s' "$LAST_OUT" | grep -cF '省いた' || true)" -gt 0 ]; then
  ok "★ 省いたことを必ず出力する（黙って飛ばさない）"
else ng "省いたのに出力していない"; fi

rm -f "$SANDBOX/calls.log"
q 0 "★ scope が違えば省かない（docs の記録で all を省くとコード検査が飛ぶ）" spec
if has_call "quality scope=docs"; then ok "→ docs で走り直した"; else ng "scope 不一致を省いてしまった"; fi

rm -f "$SANDBOX/calls.log"
echo dirty > "$SANDBOX/repo/e.txt"
q 0 "作業ツリーが dirty なら走らせる" feature
if has_call "quality scope=all"; then ok "→ 走った"; else ng "dirty なのに省いた"; fi
rm -f "$SANDBOX/repo/e.txt"

rm -f "$SANDBOX/calls.log"
printf 'こわれた記録\n' > "$(rec_file)"
q 0 "記録が壊れていたら走らせる（安全側）" feature
if has_call "quality scope=all"; then ok "→ 走った"; else ng "壊れた記録で省いた"; fi

# ★ 記録の SHA が HEAD と違えば走らせる（機構の中核。落とすと二度と走らなくなる）
rm -f "$SANDBOX/calls.log"
printf '%s all full=0\n' "0000000000000000000000000000000000000000" > "$(rec_file)"
q 0 "★ 記録の SHA が HEAD と違えば走らせる" feature
if has_call "quality scope=all"; then ok "→ 走った"; else ng "SHA 不一致なのに省いた"; fi

# ★ QUALITY_FULL_SCAN の値も記録の鍵（差分だけで通った記録で全走査を省かない）
rm -f "$SANDBOX/calls.log"
q 0 "（前提）記録を作る" feature >/dev/null; PASSED=$((PASSED - 1))
rm -f "$SANDBOX/calls.log"
out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" QUALITY_FULL_SCAN=1 bash -c \
      '. scripts/flow/lib.sh; run_quality feature' 2>&1)" || true
if has_call "quality scope=all"; then ok "★ QUALITY_FULL_SCAN が記録と違えば省かない"
else ng "QUALITY_FULL_SCAN=1 なのに QUALITY_FULL_SCAN=0 の記録で省いた"; fi

rm -f "$SANDBOX/calls.log"; echo 1 > "$SANDBOX/quality_rc"; rm -f "$(rec_file)"
q 1 "品質チェックが落ちたら非ゼロ" feature
if [ -f "$(rec_file)" ]; then ng "失敗したのに記録を書いている"; else ok "★ 失敗したら記録を書かない（次回も走る）"; fi
rm -f "$SANDBOX/quality_rc"

# ★ 測定: 5 段 × 2 回の呼び出しで **10 回 → 6 回**（40% 減）
#   （spec 段だけ、品質チェックの後に仕様ファイルが変わるので省略が発火しない。
#    モデルが居ない砂場では task-run.sh の「ステータスを completed にする」指示を fixture で再現する）
setup_sandbox; rm -f "$SANDBOX/calls.log"; rm -f "$(rec_file)"
for kind in survey spec feature validation experiment; do
  # ★ 各段は自分の成果物をコミットしてから品質チェックに入る（本番と同じ）。
  #   これが無いと、段をまたいで HEAD も scope も変わらず**現実より省きすぎる**
  printf '%s の成果物\n' "$kind" >> "$SANDBOX/repo/a.txt"
  ( cd "$SANDBOX/repo" && git add a.txt && git commit -qm "$kind の作業" ) >/dev/null
  q 0 "（測定）$kind 段 1 回目" "$kind" >/dev/null
  # spec 段はステータス更新で作業ツリーが動く
  [ "$kind" != spec ] || { printf 'status\n' >> "$SANDBOX/repo/a.txt"
    ( cd "$SANDBOX/repo" && git add a.txt && git commit -qm "ステータス更新" ) >/dev/null; }
  q 0 "（測定）$kind 段 2 回目" "$kind" >/dev/null
done
runs="$(calls | grep -c 'quality scope=' || true)"
PASSED=$((PASSED - 10))   # 上の 10 回は測定用なので件数に数えない
if [ "$runs" -eq 6 ]; then
  ok "★ 5 段 × 2 回の呼び出しで品質チェックは 6 回だけ走る（10 → 6）"
else ng "品質チェックが $runs 回走った（期待 6。spec 段だけ 2 回のはず）"; fi

# ══════════════════════════════════════════════════════════════════
# 環境変数の裏口
# ══════════════════════════════════════════════════════════════════
echo "--- 環境変数の裏口 ---"
setup_sandbox; rm -f "$SANDBOX/calls.log"
out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" \
       QUALITY_SCOPE=docs QUALITY_BASE_BRANCH=HEAD bash -c \
       '. scripts/flow/lib.sh; run_quality feature' 2>&1)" || true
if has_call "quality scope=all base=（無し）"; then
  ok "★ QUALITY_SCOPE も QUALITY_BASE_BRANCH も環境から継承しない"
else ng "環境変数が漏れている: $(calls | tail -1)"; fi

echo
printf '成立 %d / 不成立 %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
