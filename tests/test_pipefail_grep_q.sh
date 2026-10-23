#!/usr/bin/env bash
# `set -o pipefail` のスクリプトで、早期終了する読み手（`| grep -q` / コマンド置換の中の `| head`）を禁じる。
#
# 読み手が一致した瞬間に終了すると、書き手が SIGPIPE（終了コード 141）で死ぬ。pipefail があると
# パイプライン全体が 141 になり、「一致した」のに条件が偽になる。生産者の出力がパイプバッファ（64KiB）を
# 超えるときに起きる（`seq 1 200000` や worktree の多い `git worktree list` では毎回起きる）。
# 派生プロジェクトでは worktree-setup の無言終了と、ラベル検査の誤報告として実際に起きた。
#
# 直し方: `grep -c ... -gt 0`、here-string（`grep -q ... <<<"$v"`）、`sed -n '1p'`（入力を最後まで読む）。
# この検査は「形」を固定する（挙動のテストは、その呼び出し箇所を通らない書き換えを見逃すため）。
#
# 例外: 出力だけが目的で終了コードを使わない行は、行末に `# pipefail-grep-q:allow <理由>` を付ける。

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

PASS=0
FAIL=0

check() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    echo "        期待: $want"
    echo "        実際: $got"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== pipefail のスクリプトで早期終了する読み手を使っていないこと ==="

# pipefail を使うシェルスクリプトを列挙し、`| grep -q` を探す。
# 許可マーカーが付いた行と、コメント行は除く。
BAD=""
# ★ `scripts/*.sh tests/*.sh` では**ディレクトリを跨がない**。追跡中の全 `*.sh` を見る
#   （`.claude/skills/**/*.sh` や `.devcontainer/*.sh` にも pipefail のものがある）
# ★★ **走査を関数に切り出す**。以前は同じ正規表現が
#   「本走査」と「恒真でないことの確認（positive control）」の**2 箇所に書き写されて**いた。
#   書き写した control は、本走査を直しても一緒には直らない（この検査自身が
#   「式を書き写した検査は実装を変えても落ちない」と書いている罠に落ちていた）。
#
# ★ **行継続（`\` ＋改行）を畳んでから当てる**。
#   `$(` と `| head` が別の行に割れていると、1 行に閉じた正規表現は**素通りする**。
#   実例:
#     claude_min=$(sed -n '…' \
#       .devcontainer/install-claude-native.sh | head -n1)
#   畳んだ後も**元の物理行番号**を報告する（畳んだ後の番号を出すと追えなくなる）。
fold_logical_lines() {
  awk '
    {
      if (pending) { buf = buf " " $0 } else { buf = $0; ln = NR }
      # ★ コメント行は畳まない。bash はコメント末尾の `\` を
      #   行継続と見なさないが、畳むと**直後の本物の違反がコメントに吸収されて消える**
      #   （論理行の先頭が `#` になり、コメント除外に掛かる）。実測で再現した偽陰性で、
      #   引き金になるコメント行はこのファイル自身にあった
      iscomment = ($0 ~ /^[[:space:]]*#/)
      # ★ `\` の直後に空白があると bash は継続しない（実測）。`\$` に締める
      if (!iscomment && $0 ~ /\\$/) { pending = 1; sub(/\\$/, "", buf); next }
      # ★ 行末が `|` / `||` / `&&` の場合も shell は次の行を待つ。
      #   `\` を書かずに済むので**むしろ自然な綴り**で、ここを畳まないと
      #   `V=$(cmd |` ＋改行 ＋ `  head -n1)` が素通りする。`\` と違い除去はしない
      if (!iscomment && $0 ~ /(\||&&)[[:space:]]*$/) { pending = 1; next }
      pending = 0
      print ln ":" buf
      buf = ""
    }
    END { if (pending) print ln ":" buf }
  ' "$1"
}

# `$( … | head … )` の違反を返す（`<行番号>:<論理行>` の列）。空なら違反なし
head_hits_in() {
  # shellcheck disable=SC2016  # ★ `$(` とバッククォートは**探す対象の literal** である。
  #   展開させたら検査にならないので単一引用符が正しい
  fold_logical_lines "$1" \
    | grep -E '^[0-9]+:.*(\$\(|`).*\|[[:space:]]*head([[:space:]]|\)|`|$)' \
    | grep -v 'pipefail-grep-q:allow' \
    | grep -vE '^[0-9]+:[[:space:]]*#' || true
}

# `… | grep -q …` の違反を返す（同じ形）
grepq_hits_in() {
  fold_logical_lines "$1" \
    | grep -E '^[0-9]+:.*(^|[^|])\|[[:space:]]*grep[[:space:]]+(-[a-zA-Z]*q|--quiet)' \
    | grep -v 'pipefail-grep-q:allow' \
    | grep -vE '^[0-9]+:[[:space:]]*#' || true
}

UNREADABLE=""
# source される側も対象にするため、source 行を 1 回だけ集める（ファイルごとに git grep すると遅い）
SOURCE_LINES=$(git grep -h -E '^[[:space:]]*(\.|source)[[:space:]]' -- '*.sh' || true)
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # ★ **読めないファイルを黙って「違反なし」にしない**。
  #   `head_hits_in` / `grepq_hits_in` の末尾の `|| true` は grep の
  #   「一致なし（rc=1）」と「エラー（rc=2。正規表現の破損・ファイルが開けない）」を
  #   区別しないので、開けないファイルは**空の結果＝違反なし**として通ってしまう。
  #   正規表現の破損は positive control が捕まえるが、ファイル単位の失敗は捕まえられない
  if [ ! -r "$f" ]; then
    UNREADABLE="${UNREADABLE}${f}
"
    continue
  fi
  # ★ ここで `| grep -q` を使わない（この検査自身が同じ罠に落ちる）
  # ★ **source される側は自分で pipefail を設定しない**ので、文字列で足切りすると
  #   漏れる（/review 2 回目 C-2。述語を別ファイルに切り出した瞬間に網から外れた）。
  #   `. "..."` / `source "..."` で読み込まれるファイルも対象にする
  # ★ 足切りを 2 つ広げた。
  #   旧条件（pipefail を含む or source される）では **旧マージスクリプト（set -e のみ）** と
  #   **scripts/flow/issue-branch.sh（どちらにも当たらない）** が素通りしていた。
  #   実測: `set -e` を足すと 7 本増え、**新たに検出される違反は旧マージスクリプトの 1 件だけ**だった。
  if [ "$(grep -c 'pipefail' "$f")" -eq 0 ] \
     && [ "$(grep -c -- "$(basename "$f")" <<<"$SOURCE_LINES" || true)" -eq 0 ] \
     && [ "$(grep -cE '^set -e' "$f")" -eq 0 ] \
     && [ "$(grep -cE "^[[:space:]]*(\.|source)[[:space:]].*lib\.sh" "$f")" -eq 0 ]; then
    continue
  fi
  # ★ `||`（論理和）の 2 本目の `|` を拾わないよう、直前が `|` でないことを要求する。
  #   実測: これを入れないと `[ -d tests ] || grep -q ... file` を誤検出した
  hits=$(grepq_hits_in "$f")
  # ★ `$( ... | head ... )` も見る。**実害を出していたのはこちらだった**
  #   （`scripts/safe-remove-worktree.sh:41` の `$(git worktree list | head -1 | awk ...)` が
  #   worktree 42 本で 10/10 失敗し、`/worktree-safe-remove` を壊していた）。
  #   コマンド置換の中は終了コードが代入に伝わるので危険度が高い
  head_hits=$(head_hits_in "$f")
  if [ -n "$hits" ] || [ -n "$head_hits" ]; then
    BAD="${BAD}${f}:
${hits}${head_hits}
"
  fi
done < <(git ls-files '*.sh')

check "pipefail のスクリプトに early-exit な grep が無い" "${BAD:-none}" "none"
# ★ 走査できなかったファイルがあれば落とす（「違反なし」と区別する）
check "走査できなかったファイルが無い" "${UNREADABLE:-none}" "none"

# ---------------------------------------------------------------------------
# この検査が空振りしていないこと（恒真でないことの確認）
#
# ★ **検出できることを実証する。** わざと違反を作った一時ファイルを同じ規則で走査し、
#    見つかることを確かめる。見つからなければ規則が壊れている。
# ---------------------------------------------------------------------------
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
# ★ 違反の文字列を**この検査のソースに literal で置かない**（自分を誤検出するため）。
#   組み立てて書き出す
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  printf 'if printf %s | grep %sq b; then echo found; fi\n' "'a\\nb\\n'" "-"
} > "$TMPD/violation.sh"
# ★ **本走査と同じ関数を通す**。別に書き写すと control だけが古くなる
FOUND=$(grepq_hits_in "$TMPD/violation.sh")
check "わざと作った違反を検出できる" "$([ -n "$FOUND" ] && echo detected || echo missed)" "detected"

# ★ `head` の規則も空振りしていないこと
#   （**実害を出していたのはこちらだった**ので、対照が無いと片手落ちになる）
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'M=$(git worktree list | head %s1 | awk "{print \\$1}")\n' "-"  # pipefail-grep-q:allow わざと作る違反の雛形
} > "$TMPD/head_violation.sh"
HEAD_FOUND=$(head_hits_in "$TMPD/head_violation.sh")
check "コマンド置換の中の '| head' を検出できる" \
      "$([ -n "$HEAD_FOUND" ] && echo detected || echo missed)" "detected"

# ★★ **行継続で割れた違反も検出できること**。
#   `$(` と `| head` が別の物理行にあると、1 行に閉じた正規表現は素通りしていた。
#   派生プロジェクトで実際にこの形が入り、ゲートが素通りした
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'V=$(sed -n %s file \\\n' "'1p'"
  printf '  | head %s1)\n' "-"            # pipefail-grep-q:allow わざと作る違反の雛形
} > "$TMPD/head_wrapped.sh"
WRAPPED=$(head_hits_in "$TMPD/head_wrapped.sh")
check "行継続で割れた '| head' を検出できる" \
      "$([ -n "$WRAPPED" ] && echo detected || echo missed)" "detected"
# ★ 報告する行番号が**畳む前の物理行**であること（追えなくなるので）
check "行継続の違反を元の行番号で報告する" \
      "$(printf '%s' "$WRAPPED" | cut -d: -f1)" "3"

# ★★ 以下はレビューで「まだ素通りする」と実測した綴り。**どれも valid な bash**。
#   割り方が 1 文字違うだけで緑になるので、形ごとに control を置く
#
# (a) パイプを行末に置く形（`\` を書かずに済むので**むしろ自然**）
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'V=$(sed -n %s f |\n' "'1p'"
  printf '  head %s1)\n' "-"               # pipefail-grep-q:allow わざと作る違反の雛形
} > "$TMPD/head_pipe_eol.sh"
check "行末のパイプで割れた '| head' を検出できる" \
      "$([ -n "$(head_hits_in "$TMPD/head_pipe_eol.sh")" ] && echo detected || echo missed)" \
      "detected"

# (b) バッククォートのコマンド置換
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'V=`sed -n %s f | head %s1`\n' "'1p'" "-"   # pipefail-grep-q:allow わざと作る違反の雛形
} > "$TMPD/head_backtick.sh"
check "バッククォート置換の中の '| head' を検出できる" \
      "$([ -n "$(head_hits_in "$TMPD/head_backtick.sh")" ] && echo detected || echo missed)" \
      "detected"

# (c) ★ 末尾が `\` のコメント行の**次**にある違反。
#   bash はコメント末尾の `\` を継続と見ないので、畳むと違反がコメントに吸収されて消えていた
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf '# 禁止形の説明 \\\n'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'V=$(cat f | head %s1)\n' "-"     # pipefail-grep-q:allow わざと作る違反の雛形
} > "$TMPD/head_after_comment.sh"
AFTER_COMMENT=$(head_hits_in "$TMPD/head_after_comment.sh")
check "末尾が \\ のコメント行の次の違反を検出できる" \
      "$([ -n "$AFTER_COMMENT" ] && echo detected || echo missed)" "detected"
# ★ コメント（3 行目）ではなく**違反のある 4 行目**を報告すること
check "コメントに吸収されず違反の行番号を報告する" \
      "$(printf '%s' "$AFTER_COMMENT" | cut -d: -f1)" "4"

# ---------------------------------------------------------------------------
# ★ 誤検出しないこと（negative control）。検出を広げたので、逆向きも固定する
# ---------------------------------------------------------------------------
# (d) `\` の直後に空白がある行は bash が継続しない → 畳んではいけない
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf 'echo A \\ \n'
  # shellcheck disable=SC2016  # 展開させずに literal を書き出すのが目的
  printf 'V=$(cat f)\n'
} > "$TMPD/bs_space.sh"
check "'\\' ＋空白は継続として畳まない（bash と同じ）" \
      "$(head_hits_in "$TMPD/bs_space.sh" || true)" ""

# (e) `||`（論理和）の 2 本目の `|` を `| grep -q` と読み違えない
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf '[ -d x ] || grep %sq a f\n' "-"
} > "$TMPD/oror.sh"
check "'|| grep -q' を誤検出しない" "$(grepq_hits_in "$TMPD/oror.sh" || true)" ""

# (f) コメントの中で禁止形に**言及**しているだけの行を誤検出しない
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  # ★ `$(` を 2 つに割って渡す。**繋げて書くとこのファイル自身が違反として検出される**
  #   （冒頭の「違反の文字列をこの検査のソースに literal で置かない」。実際に踏んだ）
  printf '# V=%s(cat f | head %s1) は禁止\n' '$' "-"
  echo 'echo ok'
} > "$TMPD/mention.sh"
check "コメント中の言及を誤検出しない" "$(head_hits_in "$TMPD/mention.sh" || true)" ""

# 走査対象が空でないこと（空なら検査全体が恒真になる）
check "走査対象が空でない" "$([ "$(git ls-files '*.sh' | grep -c .)" -gt 0 ] && echo yes || echo no)" "yes"

# 許可マーカーが効くこと
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  printf 'printf %s | grep %sq a  # pipefail-grep-q:allow 出力のみ\n' "'a\\n'" "-"
} > "$TMPD/allowed.sh"
ALLOWED=$(grepq_hits_in "$TMPD/allowed.sh")
check "許可マーカーが効く" "${ALLOWED:-none}" "none"

# ---------------------------------------------------------------------------
# ★ positive control: 禁じている形が**本当に壊れる**ことを実証する
#
# ★ **小さい生産者で測ってはいけない。** 当初この検査は 143 バイトの入力を 300 回
#    回していたが、**壊れた版（`grep -q`）でも 0 回失敗する**ので恒真だった。
#    パイプバッファ（64KiB）を超える生産者でなければ SIGPIPE が起きない。
# ---------------------------------------------------------------------------
BROKEN=0
for _ in $(seq 5); do
  if ! (set -uo pipefail; seq 1 200000 | grep -qx -- 1); then  # pipefail-grep-q:allow 禁じている形が壊れることの実証（positive control）
    BROKEN=$((BROKEN + 1))
  fi
done
check "禁じている形は 64KiB 超の入力で必ず壊れる（5/5）" "$BROKEN" "5"

FIXED=0
for _ in $(seq 5); do
  if [ "$(set -uo pipefail; seq 1 200000 | grep -cx -- 1)" -eq 0 ]; then
    FIXED=$((FIXED + 1))
  fi
done
check "直した形は同じ入力で一度も壊れない（0/5）" "$FIXED" "0"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
