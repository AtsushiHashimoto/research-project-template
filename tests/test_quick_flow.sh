#!/usr/bin/env bash
#
# scripts/flow/quick.sh の自己検証。
#
# ★ **検査が「落ちること」を、項目ごとに単独で確かめる。**
#   存在だけを見る検査は恒真になり（壊しても緑のまま）、
#   規律を完璧に守っても落ちる検査は恒偽になる（正しくても赤）。**両方を見る。**
#
# 仕様: .spec/issues/185-flow-port.md §7（validation の判定項目）。§7-1 などの節番号はこのファイルの中の見出し
#
# ★ **上限の 3 / 50 は直書きする。** `quick.sh` の定数を読むと、値を変えた瞬間に
#   検査が黙って追随して恒真になる（独立オラクル。値を直書きする形）。
#
# 実行:  ./tests/test_quick_flow.sh
# 終了:  0 全て成立 / 1 いずれか不成立
#
# ★ `| grep -q` / `| head ` を使わない（pipefail 下の SIGPIPE）。

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
count_in_code() {  # count_in_code <ファイル> <ERE>
  local body; body="$(code_of "$1")"
  printf '%s' "$body" | grep -cE -e "$2" || true
}

SANDBOX="$(mktemp -d)" || { echo "mktemp -d が失敗した" >&2; exit 1; }
[ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] || { echo "砂場を作れない" >&2; exit 1; }
export SB="$SANDBOX"
trap 'rm -rf "${SANDBOX:?}"' EXIT
mkdir -p "${SANDBOX:?}/bin"

echo "=== flow/quick.sh の自己検証==="

# ══════════════════════════════════════════════════════════════════
# 静的な性質
# ══════════════════════════════════════════════════════════════════
echo "--- 静的な性質 ---"

n="$(wc -l <"$FLOW/quick.sh")"
if [ "$n" -le 300 ]; then ok "quick.sh は $n 行（上限 300）"
else ng "quick.sh は $n 行で上限 300 を超える"; fi

if [ "$(count_in_code "$FLOW/quick.sh" '\|[[:space:]]*(grep -q|head )')" -gt 0 ]; then  # pipefail-grep-q:allow 検出対象の綴りそのもの
  ng "quick.sh に pipefail の禁止形がある"
else ok "quick.sh に pipefail の禁止形が無い"; fi

# ★ 検査 11: 上限の定数は 1 箇所だけ
for c in QUICK_MAX_FILES=3 QUICK_MAX_LINES=50; do
  if [ "$(count_in_code "$FLOW/quick.sh" "readonly $c")" -eq 1 ]; then
    ok "上限の定数 $c は quick.sh に 1 つだけ"
  else ng "上限の定数 $c が 1 つでない"; fi
done

# ★ 検査 12: 述語を写経していない（既存へ移譲する）
# ★ **案内文ではなく実際の呼び出しに当てる**（/review の指摘）。
#   `'commit\.sh push'` は `commit.sh" push`（間に `"` がある）に一致せず、
#   出力の案内文にだけ当たっていた（＝呼び出しを消しても緑のままだった。実測）
# shellcheck disable=SC2016  # 検出したい**綴りそのもの**なので展開させない
for pat in 'issue-create\.sh" --type chore' 'issue-start\.sh" "\$num"' 'commit\.sh" push'; do
  if [ "$(count_in_code "$FLOW/quick.sh" "$pat")" -gt 0 ]; then
    ok "quick.sh は $pat を実際に呼ぶ（案内文ではない）"
  else ng "quick.sh が $pat を呼んでいない"; fi
done
if [ "$(count_in_code "$FLOW/quick.sh" 'gh issue create')" -eq 0 ]; then
  ok "quick.sh は gh issue create を直に呼ばない"
else ng "quick.sh が gh issue create を直に呼んでいる"; fi
# ★ 計測では index に触らない（`git add -N` で数えない）。stage は上限を通った後に名指しで行う
if [ "$(count_in_code "$FLOW/quick.sh" 'git add (-N|-A|--all|\.)')" -eq 0 ]; then
  ok "quick.sh は git add -N / -A / . を使わない"
else ng "quick.sh が git add -N / -A / . を使っている"; fi

# ★ 検査 20: 接頭辞の対応表が chore:chore になっている
if [ "$(count_in_code "$REPO_ROOT/tests/test_issue_flow.sh" 'chore:chore')" -gt 0 ]; then
  ok "★ tests/test_issue_flow.sh の対応表が chore:chore（branch_prefix と揃っている）"
else ng "接頭辞の対応表が chore:chore になっていない（branch_prefix と食い違う）"; fi
if [ "$(count_in_code "$FLOW/lib.sh" "chore\\)[[:space:]]*printf 'chore'")" -gt 0 ]; then
  ok "★ branch_prefix が chore → chore（chore/<N>-* の枝ができる）"
else ng "branch_prefix が chore → chore になっていない"; fi


# ══════════════════════════════════════════════════════════════════
# 砂場
# ══════════════════════════════════════════════════════════════════
make_gh() {
  cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
f="$SB/issues.txt"
case "$1 $2" in
  "repo view") echo "x/y"; exit 0;;
esac
if [ "$1" = issue ] && [ "$2" = view ]; then
  r="$(grep -E "^$3:" "$f" || true)"; [ -n "$r" ] || { echo "not found" >&2; exit 1; }
  IFS=: read -r _ labels state title <<< "$r"
  json=""; prev=""
  for a in "$@"; do [ "$prev" = "--json" ] && json="$a"; prev="$a"; done
  case "$json" in
    labels) echo "$labels";; state) echo "$state";;
    parent) echo "";;               # ★ 親は無い（chore の単独 issue）
    *)      echo "$title";;
  esac
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = list ]; then
  printf '%s\n' ${GH_PR:-}; exit 0
fi
if [ "$1" = pr ] && [ "$2" = create ]; then
  printf 'gh pr create\n' >> "$SB/calls.log"
  # ★ **本文を記録する**。本文が `/review` を飛ばせる形に戻っても
  #   検査が気づかなかった（壊しても緑のままだった）
  prev=""; for a in "$@"; do [ "$prev" = "--body" ] && printf '%s' "$a" > "$SB/pr_body.txt"; prev="$a"; done
  echo "https://x/y/pull/1"; exit 0
fi
if [ "$1" = label ] && [ "$2" = list ]; then
  # ★ issue-create.sh は `--jq '[.[].name]|join(",")'` で受けるので**カンマ区切り 1 行**を返す
  echo "epic,task,survey,spec,feature,validation,experiment,bug,docs,refactor,chore"
  exit 0
fi
if [ "$1" = issue ] && [ "$2" = create ]; then
  printf 'gh issue create\n' >> "$SB/calls.log"
  echo "https://x/y/issues/${GH_NEW:-950}"; exit 0
fi
if [ "$1" = issue ] && { [ "$2" = comment ] || [ "$2" = edit ]; }; then
  printf 'gh issue %s %s\n' "$2" "$3" >> "$SB/calls.log"; exit 0
fi
if [ "$1" = api ]; then
  printf 'gh api\n' >> "$SB/calls.log"; echo "999888"; exit 0
fi
# ★ 知らない呼び出しは大声で落とす（空出力で緑になるのを防ぐ）
printf '偽 gh: 未対応の呼び出し: %s\n' "$*" >&2
exit 1
STUB
  chmod +x "$SANDBOX/bin/gh"
}

FIXTURE='901:chore:OPEN:軽微な直し
902:feature:OPEN:軽微でない
903:chore:CLOSED:閉じた chore
950:chore:OPEN:軽微な直し
'

setup_sandbox() {
  local R="$SANDBOX/repo"
  rm -rf "$R"; mkdir -p "$R/scripts/flow"
  cp "$FLOW"/*.sh "$R/scripts/flow/"
  cp "$REPO_ROOT/scripts/check-discipline.sh" "$REPO_ROOT/scripts/check-discipline-predicates.sh" "$R/scripts/"
  # ★ worktree の作成はこれを通す（偽物を置かない。実物で動かす）
  cp "$REPO_ROOT/scripts/worktree-relative.sh" "$R/scripts/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/configure-agent-workflow.sh"
  cat > "$R/scripts/quality-check.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  # ★ 偽の setup-worktree.sh（issue-start.sh が data/shared の symlink を要求する）
  # ★ issue-start.sh は data/shared が**共有ストアに解決するか**で判定する。
  #   ストアの場所は実物の scripts/lib/shared-store.sh と .claude/worktree-config.json から引く
  mkdir -p "$R/scripts/lib" "$R/.claude" "$R/data/shared"
  cp "$REPO_ROOT/scripts/lib/shared-store.sh" "$R/scripts/lib/"
  printf '{"shared_data_path": "data/shared", "path_type": "relative"}\n' > "$R/.claude/worktree-config.json"
  cat > "$R/scripts/setup-worktree.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p data
ln -sfn "$SB/repo/data/shared" data/shared
SH
  chmod +x "$R/scripts"/*.sh "$R/scripts/flow"/*.sh
  rm -rf "$SANDBOX/remote.git"; git init -q --bare "$SANDBOX/remote.git"
  ( cd "$R" && git init -q -b main . && git config user.email t@e.x && git config user.name t \
    && echo base > a.txt && git add -A && git commit -qm base \
    && git remote add origin "$SANDBOX/remote.git" \
    && git push -q origin main \
    && git checkout -q -b "chore/901-i901" ) >/dev/null 2>&1
  rm -f "$SANDBOX/calls.log" "$SANDBOX/pr_body.txt"
  printf '%s' "$FIXTURE" > "$SANDBOX/issues.txt"
  unset GH_PR
  # ★ セットアップの失敗を黙らせない（/review の指摘）。枝が main のままだと
  #   `run 1` 系が**別の理由で**緑になる（壊しても緑のままになる形）
  [ "$(git -C "$R" symbolic-ref --quiet --short HEAD 2>/dev/null)" = "chore/901-i901" ] \
    || ng "（前提）砂場が chore/901-i901 に居ない"
}

# run <期待コード> <説明> <引数...>
run() {
  local want="$1" what="$2"; shift 2
  local out rc
  out="$(cd "$SANDBOX/repo" && PATH="$SANDBOX/bin:$PATH" \
         bash "$SANDBOX/repo/scripts/flow/quick.sh" "$@" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then ok "$what"; else
    ng "$what（期待 $want、実際 $rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/        /'
  fi
}
said() { [ "$(printf '%s' "$LAST_OUT" | grep -cF "$1" || true)" -gt 0 ]; }
has_call() { [ "$(grep -cF "$1" "$SANDBOX/calls.log" 2>/dev/null || true)" -gt 0 ]; }

# lines_of <行数>  指定した行数のテキストを作る
lines_of() { local i; for i in $(seq 1 "$1"); do printf 'line%s\n' "$i"; done; }

make_gh
setup_sandbox

echo "--- 引数 ---"
run 1 "サブコマンドが無いと落ちる"
run 1 "未知のサブコマンドで落ちる" nonsense
run 1 "finish に --issue が無いと落ちる（★ ブランチ名から推測しない）" finish --message x
run 1 "finish に --message が無いと落ちる（文言を捏造しない）" finish --issue 901
run 1 "finish の --issue が数値でないと落ちる" finish --issue abc --message x
run 1 "未知のオプションで落ちる" finish --issue 901 --message x --lable y

echo "--- 上限（★ 3 と 50 は直書き。定数を読まない）---"
# 1: ファイル数
setup_sandbox
( cd "$SANDBOX/repo" && for i in 1 2 3; do printf 'a\n' > "f$i.txt"; done )
run 0 "3 ファイルは通る（恒偽でない）" finish --issue 901 --message "3 ファイル"
# ★ **肯定側**（/review の指摘）。否定側（「超過時に PR を作らない」）だけだと、
#   PR 作成もコミットも**消してしまえば自動的に成立する**（壊しても緑のままになる形）
if has_call "gh pr create"; then ok "★ 上限の内側なら PR を作る（作る側の主張）"
else ng "上限の内側なのに PR を作っていない"; fi
if [ "$(cd "$SANDBOX/repo" && git log -1 --format=%B | grep -cF 'Refs #901' || true)" -gt 0 ]; then
  ok "★ Refs #901 付きのコミットができている（commit.sh へ移譲できている）"
else ng "Refs #901 のコミットが無い（コミットしていない）"; fi
if [ "$(cd "$SANDBOX/repo" && git ls-remote --heads origin "chore/901-i901" | grep -c . || true)" -gt 0 ]; then
  ok "★ origin に push されている"
else ng "push されていない"; fi
# ★ **PR 本文が `/review` の門を開けないこと**。
#   `check_pr_review` と**同じ awk** を掛け、この時点では**まだ通らない**ことを見る。
#   見出しの下に但し書きを 1 行置くだけで通ってしまうのが、/review で見つかった Critical
review_ok() {  # review_ok <本文ファイル> → 0 なら check_pr_review が通る
  awk '
    { sub(/\r$/, "") }
    /^#+[[:space:]]*\/review[[:space:]]*結果/ { seen=1; next }
    seen && /^#/ { exit }
    seen && NF { found=1; exit }
    END { exit !found }' "$1"
}
if [ -s "$SANDBOX/pr_body.txt" ]; then
  if review_ok "$SANDBOX/pr_body.txt"; then
    ng "★ PR 本文が check_pr_review を通ってしまう（/review を回さずにマージできる）"
  else ok "★ PR 本文は check_pr_review を通らない（/review を省けない）"; fi
  if [ "$(grep -cF '## /review 結果' "$SANDBOX/pr_body.txt" || true)" -gt 0 ]; then
    ok "★ PR 本文に '## /review 結果' の見出しはある（/review の置き場がある）"
  else ng "PR 本文に '## /review 結果' の見出しが無い"; fi
  if [ "$(grep -cE '^(Closes|Fixes) #' "$SANDBOX/pr_body.txt" || true)" -eq 0 ]; then
    ok "★ PR 本文に Closes/Fixes を書かない（GitHub の自動 close を起こさない）"
  else ng "PR 本文が Closes/Fixes を書いている（issue-finish.sh の完了報告が残らなくなる）"; fi
else ng "PR 本文が記録されていない（gh pr create を呼んでいない）"; fi
setup_sandbox
( cd "$SANDBOX/repo" && for i in 1 2 3 4; do printf 'a\n' > "f$i.txt"; done )
run 1 "★ 4 ファイルで落ちる" finish --issue 901 --message "4 ファイル"
if said "上限を超えている"; then ok "→ 落ちた理由が上限である"; else ng "上限以外の理由で落ちている"; fi
if has_call "gh pr create"; then ng "上限超過なのに PR を作っている"; else ok "→ gh pr create を呼ばない（検査 10）"; fi

if [ -z "$(git -C "$SANDBOX/repo" diff --cached --name-only)" ]; then ok "★ 上限超過で落ちたとき index に何も stage していない"
else ng "上限超過で落ちたのに index に stage が残っている"; fi

# ★ 上限の検査に数えたファイルだけを名指しで stage する（.gitignore 対象・数えないものは入らない）
setup_sandbox
( cd "$SANDBOX/repo" && printf 'changed\n' >> a.txt && printf 'new\n' > "new file.txt" \
  && printf 'ignored.log\n' > .git/info/exclude && printf 'x\n' > ignored.log )
run 0 "追跡済みの変更 1 つ＋空白を含む新規 1 つで finish が通る" finish --issue 901 --message "名指し"
got="$(git -C "$SANDBOX/repo" show --name-only --format= HEAD | sort | tr '\n' '|')"
if [ "$got" = "a.txt|new file.txt|" ]; then ok "★ コミットの中身は数えたファイル（a.txt と new file.txt）だけ"
else ng "コミットの中身が数えたファイルと違う: $got"; fi
setup_sandbox
( cd "$SANDBOX/repo" && git rm -q a.txt )
run 0 "削除だけの変更でも finish が通る" finish --issue 901 --message "削除"
if [ "$(git -C "$SANDBOX/repo" show --name-status --format= HEAD | grep -c '^D[[:space:]]*a.txt$' || true)" -eq 1 ]; then
  ok "★ 削除したファイルも名前で stage される"
else ng "削除が コミットに入っていない"; fi
setup_sandbox
( cd "$SANDBOX/repo" && rm a.txt )
run 0 "stage していない削除（rm だけ）でも finish が通る" finish --issue 901 --message "rm だけ"
if [ "$(git -C "$SANDBOX/repo" show --name-status --format= HEAD | grep -c '^D[[:space:]]*a.txt$' || true)" -eq 1 ]; then
  ok "★ rm しただけのファイルも git rm --cached で名指しして削除をコミットに入れる"
else ng "rm しただけの削除がコミットに入っていない"; fi

# 2: 行数
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 50 > big.txt )
run 0 "50 行は通る（恒偽でない）" finish --issue 901 --message "50 行"
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 51 > big.txt )
run 1 "★ 51 行で落ちる" finish --issue 901 --message "51 行"

# 3: 追加 + 削除の合計
# ★ **基点（main）に置いてから枝を切る。** 枝の上で作ったファイルは「追加」しか出ない
seed_on_main() {  # seed_on_main <行数>  main に tracked.txt を置いてから枝へ戻る
  setup_sandbox
  ( cd "$SANDBOX/repo" && git checkout -q main && lines_of "$1" > tracked.txt \
    && git add -A && git commit -qm seed && git push -q origin main \
    && git checkout -q "chore/901-i901" && git merge -q main ) >/dev/null 2>&1
}
seed_on_main 25
( cd "$SANDBOX/repo" && lines_of 25 | sed 's/line/LINE/' > tracked.txt )
run 0 "25 追加 + 25 削除（合計 50）は通る" finish --issue 901 --message "50"
seed_on_main 25
( cd "$SANDBOX/repo" && { lines_of 25 | sed 's/line/LINE/'; printf 'extra\n'; } > tracked.txt )
run 1 "★ 26 追加 + 25 削除（合計 51）で落ちる（追加だけで数えない）" finish --issue 901 --message "51"

# 5: コミットを分けても回避できない
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 30 > c1.txt && git add -A && git commit -qm c1 \
  && lines_of 30 > c2.txt && git add -A && git commit -qm c2 )
run 1 "★ 30 行 × 2 コミットでも落ちる（コミットを分けて回避できない）" finish --issue 901 --message "60"

# 13: 追跡外のファイルだけで超過する（M3 の抜け道）
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 51 > untracked.txt )   # add しない
run 1 "★ 追跡外のファイルだけで 51 行でも落ちる（git diff は見ない）" finish --issue 901 --message "untracked"
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 50 > untracked.txt )
run 0 "追跡外 50 行は通る（恒偽でない）" finish --issue 901 --message "untracked 50"

# 4: 除外しない（**追跡されている生成物**で 51 行）
# ★ .gitignore 対象は数えず、stage もしないので抜け道にならない
#   （実測で確認済み）。守るべきは「将来だれかが除外リストを足したら落ちる」こと
setup_sandbox
( cd "$SANDBOX/repo" && mkdir -p data/shared && lines_of 51 > data/shared/results.csv )
run 1 "★ 生成物（data/shared/）でも数える（除外しない）" finish --issue 901 --message "generated"

# 6: 保護ブランチ（commit.sh へ移譲して成立する）
setup_sandbox
( cd "$SANDBOX/repo" && git checkout -q main && printf 'a\n' > f.txt )
run 1 "★ main で finish すると落ちる（commit.sh の current_branch へ移譲）" finish --issue 901 --message x
if said "に居る"; then ok "→ 落ちた理由がブランチである"; else ng "ブランチ以外の理由で落ちている"; fi

# 18: **追跡済み**のバイナリ（numstat が `-` を返す経路。追跡外とは別の目）
setup_sandbox
( cd "$SANDBOX/repo" && head -c 3000 /dev/urandom > tracked.bin && git add -A )
run 1 "★ 追跡済みのバイナリでも落ちる（numstat の - を 0 行と読まない）" finish --issue 901 --message bin
if said "バイナリの変更がある"; then ok "→ 追跡側の die 経路を踏んでいる"
else ng "追跡側のバイナリ検査を踏んでいない"; fi

# 17: 基点が進んでも自分の変更だけを数える（N2）
setup_sandbox
( cd "$SANDBOX/repo" && git checkout -q main && lines_of 100 > mainwork.txt \
  && git add -A && git commit -qm mainwork && git push -q origin main \
  && git checkout -q "chore/901-i901" && lines_of 10 > mine.txt )
run 0 "★ 基点が 100 行進んでも、自分の 10 行だけを数える" finish --issue 901 --message "10"

# 18: バイナリ（N3-a）
setup_sandbox
( cd "$SANDBOX/repo" && head -c 3000 /dev/urandom > bin.dat )
run 1 "★ 追跡外のバイナリがあると落ちる（改行バイトを行数として数えない）" finish --issue 901 --message "bin"
if said "バイナリ"; then ok "→ 落ちた理由がバイナリである"; else ng "バイナリ以外の理由で落ちている"; fi

# 19: サブディレクトリから叩いても数える（N3-b）
setup_sandbox
( cd "$SANDBOX/repo" && mkdir -p sub && lines_of 51 > root.txt && printf 'x\n' > sub/s.txt )
out="$(cd "$SANDBOX/repo/sub" && PATH="$SANDBOX/bin:$PATH" \
       bash "$SANDBOX/repo/scripts/flow/quick.sh" finish --issue 901 --message sub 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && [ "$(printf '%s' "$out" | grep -cF '上限を超えている' || true)" -gt 0 ]; then
  ok "★ サブディレクトリから叩いても、リポジトリ直下の 51 行を数える"
else ng "サブディレクトリから叩くと数え漏れる（rc=$rc）"; fi

# 23 / 24: 空ファイルと非 ASCII のファイル名（P2）
setup_sandbox
( cd "$SANDBOX/repo" && : > empty.txt && printf 'a\n' > "日本語 の 名前.txt" )
run 0 "★ 空の新規ファイルと非 ASCII のファイル名があっても死なない" finish --issue 901 --message "p2"
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 51 > "空白 入り.txt" )
run 1 "★ 空白入りのファイル名でも数える" finish --issue 901 --message "p2b"

# 21: index を汚さない
setup_sandbox
( cd "$SANDBOX/repo" && lines_of 51 > over.txt )
before="$(cd "$SANDBOX/repo" && git status --porcelain)"
run 1 "（前提）上限超過で落ちる" finish --issue 901 --message "index"
after="$(cd "$SANDBOX/repo" && git status --porcelain)"
if [ "$before" = "$after" ]; then ok "★ 落ちた後も index / 作業ツリーの状態が変わらない"
else ng "index を汚している（前: $before / 後: $after）"; fi

echo "--- issue の状態と種類 ---"
setup_sandbox
( cd "$SANDBOX/repo" && printf 'a\n' > f.txt )
run 1 "closed な issue で落ちる" finish --issue 903 --message x
if said "open でない"; then ok "→ 落ちた理由が open 確認である"; else ng "open 確認を素通りしている"; fi
setup_sandbox
( cd "$SANDBOX/repo" && printf 'a\n' > f.txt )
run 1 "★ 種類が chore でないと落ちる（quick は chore だけ）" finish --issue 902 --message x
if said "chore ではない"; then ok "→ 落ちた理由が種類ラベルである"; else ng "種類の検査を素通りしている"; fi

echo "--- start ---"
# 7: dirty を落とす
setup_sandbox
( cd "$SANDBOX/repo" && git checkout -q main && printf 'dirty\n' > d.txt )
run 1 "★ start は作業ツリーが dirty だと落ちる（移送しない）" start "軽微な直し"
if said "コミットしていない変更がある"; then ok "→ 落ちた理由が dirty である"; else ng "dirty 以外の理由で落ちている"; fi
# 8: issue のブランチに居ると落ちる
setup_sandbox
run 1 "★ start は issue のブランチに居ると落ちる（既定ブランチから呼ぶ）" start "軽微な直し"
if said "既定ブランチから呼ぶ"; then ok "→ 落ちた理由がブランチである"; else ng "ブランチ以外の理由で落ちている"; fi
run 1 "start に題が無いと落ちる" start

# ★ **落ちない側**（恒偽でないことの確認。/review の指摘）。
#   start の成功経路（issue 作成 → 枝と worktree）は、これまで一度も踏まれていなかった
setup_sandbox
( cd "$SANDBOX/repo" && git checkout -q main )
run 0 "★ 既定ブランチ・clean なら start は通る（恒偽でない）" start "軽微な直し"
if has_call "gh issue create"; then ok "★ issue-create.sh 経由で issue を作る"
else ng "issue を作っていない"; fi
if said "quick.sh finish --issue 950"; then
  ok "★ 次に叩く行に issue 番号と題が埋まっている（手で打ち直させない）"
else ng "次に叩く行が案内されていない"; fi
if said "終わったら、もう一度このスクリプトを同じ引数で呼ぶこと" \
   && [ "$(printf '%s' "$LAST_OUT" | grep -c '^════' || true)" -eq 2 ]; then
  ok "★ 「次にやること」の塊は 1 つだけ（子の案内を通さない）"
else ng "「次にやること」が 2 つ以上出ている（/review を飛ばす案内が混ざる）"; fi

echo
printf '成立 %d / 不成立 %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
