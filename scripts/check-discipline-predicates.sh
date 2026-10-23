#!/usr/bin/env bash
#
# 規律の述語。**定義はここだけ**。
# scripts/check-discipline.sh から読み込まれる。単体では実行しない。
#
# ★ `| grep -q` / `| head` を使わない（pipefail 下の SIGPIPE）。bash の [[ =~ ]] を使う。

# ══════════════════════════════════════════════════════════════════
# 述語
# ══════════════════════════════════════════════════════════════════

# 1. 仕様ファイル（**spec 段の issue 番号で引く**）
check_spec_file() {
  local n="$1" f first
  for f in .spec/issues/"$n"-*.md; do
    [ -e "$f" ] || continue
    case "$f" in *-auto-decisions*) continue;; esac
    nonempty "$f" || continue
    first="$(head -n 1 "$f")"
    [[ "$first" == \#* ]] || continue
    refs_n "$first" "$n" || continue
    pass "仕様ファイル ($f)"; return 0
  done
  fail "仕様ファイル: .spec/issues/$n-*.md が無い / 空 / 1 行目の見出しに #$n が無い"
}

# 2. auto-reviewer の判断ログ
check_auto_decisions() {
  local n="$1" f body
  for f in .spec/issues/"$n"-auto-decisions*.md; do
    [ -e "$f" ] || continue
    nonempty "$f" || continue
    body="$(cat "$f")"
    [[ "$body" =~ Issue[[:space:]]*\#$n([^0-9]|$) ]] || continue
    [[ "$body" == *停止条件* ]] || continue
    # ★ 停止条件（S1〜S8 の具体的な欠落）に当たっていたら進めない。
    #   「停止条件: …」の行が 1 本以上あり、**すべて**「該当なし」であること
    local line n_lines=0 hit=""
    while IFS= read -r line; do
      [[ "$line" =~ 停止条件[^:：]*[:：][[:space:]]*(.*)$ ]] || continue
      n_lines=$((n_lines + 1))
      [[ "${BASH_REMATCH[1]}" =~ ^[*\`[:space:]]*該当なし ]] || hit="$hit
     $line"
    done <<< "$body"
    if [ "$n_lines" = 0 ]; then
      fail "判断ログ $f に「停止条件: 該当なし」の形の行が無い（auto-reviewer が停止条件を判定していない）
     書く行: 停止条件: 該当なし（S1〜S8 のどれにも当たらないときだけ）"
    elif [ -n "$hit" ]; then
      fail "判断ログ $f が停止条件に該当している（仕様の欠落。進まずにユーザーへ報告する）:$hit"
    else
      pass "auto-reviewer の判断ログ ($f。停止条件: 該当なし)"
    fi
    return 0
  done
  fail "判断ログ: .spec/issues/$n-auto-decisions*.md が無い / 空 / 'Issue #$n' または '停止条件' を含まない"
}

# 3. ブランチ（★ 番号は **task の番号**。親が task でなければ issue 自身の番号）
readonly BRANCH_TYPES="feature|survey|spec|experiment|validation|fix|bug|docs|refactor|chore"
check_branch() {
  local n="$1" b
  b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$b" ] || { fail "ブランチ: detached HEAD"; return 1; }
  case "$b" in main|master) fail "ブランチ: $b に居る"; return 1;; esac
  if [[ "$b" =~ ^($BRANCH_TYPES)/$n- ]]; then
    pass "ブランチ ($b)"
  else
    fail "ブランチ: '$b' が <type>/$n-* の形でない（type は $BRANCH_TYPES）"
  fi
}

# 4. 作業差分（★ 未追跡ファイルも数える。git diff はそれを見ない）
check_worktree_diff() {
  local base tracked untracked
  base="$(resolve_base)" || { fail "作業差分: base ref を解決できない"; return 1; }
  tracked="$(git diff "$base" --stat 2>/dev/null || true)"
  untracked="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
  if [ -n "$tracked" ] || [ -n "$untracked" ]; then
    pass "作業差分 (vs $base)"
  else
    fail "作業差分: $base との差分も未追跡ファイルも無い"
  fi
}

# 4'. 現ブランチのコミットと issue の紐づけ（マージ層）
check_commit_link() {
  local n="$1" base sha
  base="$(resolve_base)" || { fail "コミット: base ref を解決できない"; return 1; }
  # ★ パイプを使わず git 側で 1 件に絞る
  sha="$(git log "$base"..HEAD --format='%H' --extended-regexp -n 1 \
          --grep="(Refs|Fixes)[[:space:]]*#${n}([^0-9]|\$)" 2>/dev/null || true)"
  if [ -n "$sha" ] && [ -n "$(git show --stat --format= "$sha" 2>/dev/null || true)" ]; then
    pass "コミット (${sha:0:8} が Refs/Fixes #$n を持ち、ファイル変更を伴う)"
  else
    fail "コミット: 'Refs #$n' / 'Fixes #$n' を持ちファイル変更を伴うコミットが $base..HEAD に無い"
  fi
}

# 4''. Closes #N のコミットを止める（GitHub が squash の時点で閉じ、issue-finish.sh の
#   完了コメントが付かない。close は issue-finish.sh だけが行う）
check_no_closes() {
  local n="$1" base sha
  base="$(resolve_base)" || { fail "Closes: base ref を解決できない"; return 1; }
  sha="$(git log "$base"..HEAD --format='%h' --extended-regexp --regexp-ignore-case -n 1 \
          --grep="(^|[^a-z])close[sd]?:?[[:space:]]*#${n}([^0-9]|\$)" 2>/dev/null || true)"
  if [ -z "$sha" ]; then pass "Closes #$n のコミットが無い"; return 0; fi
  fail "コミット $sha が 'Closes #$n' を持つ（squash で GitHub が先に閉じ、完了コメントが付かない）
     直し方: git commit --amend（または git rebase で該当コミットの本文を直す）で
     書く行: Refs #$n"
}

# マージ済みのコミットに紐づいているか（closed の feature/validation 等）
# ★ ERE と BRE を混ぜない。パイプを使わない（旧実装は両方やって恒偽だった）
check_merged_commit() {
  local n="$1" base sha
  base="$(resolve_base)" || { fail "コミット: base ref を解決できない"; return 1; }
  sha="$(git log "$base" --format='%H' --extended-regexp -n 1 \
          --grep="(Refs|Fixes)[[:space:]]*#${n}([^0-9]|\$)" 2>/dev/null || true)"
  if [ -n "$sha" ]; then
    pass "マージ済みコミット (${sha:0:8})"
  else
    fail "コミット: $base に 'Refs #$n' / 'Fixes #$n' を持つコミットが無い"
  fi
}

# 5. PR 本文の /review 結果（★ CRLF を落としてから見る）
check_pr_review() {
  local body
  body="$(gh pr view --json body -q .body 2>/dev/null || true)"
  [ -n "$body" ] || { fail "PR: 現在のブランチに PR が無い、または本文が空"; return 1; }
  if printf '%s' "$body" | awk '
      { sub(/\r$/, "") }
      /^#+[[:space:]]*\/review[[:space:]]*結果/ { seen=1; next }
      seen && /^#/ { exit }
      seen && NF { found=1; exit }
      END { exit !found }'; then
    pass "PR 本文の /review 結果"
  else
    fail "PR 本文: '/review 結果' の見出しが無い、または見出しだけで本文が無い"
  fi
}

# survey の成果物
check_survey_file() {
  local n="$1" f
  for f in docs/surveys/*.md; do
    [ -e "$f" ] || continue
    nonempty "$f" || continue
    file_refs_n "$f" "$n" || continue
    pass "survey の成果物 ($f)"; return 0
  done
  fail "survey: docs/surveys/*.md に #$n を含む非空のファイルが無い"
}

# experiment の成果物（3 点セット）
# ★ 見るのは README の**見出し行（最初の `# ` 行）**だけ。本文全体で見ると、
#   別の実験の README が #N に言及しているだけで通ってしまう
check_experiment_set() {
  local n="$1" d f title
  for f in data/shared/experiments/*/README.md; do
    [ -e "$f" ] || continue
    nonempty "$f" || continue
    title="$(grep -m1 -E '^# ' "$f")" || continue
    refs_n "$title" "$n" || continue
    d="$(dirname "$f")"
    [ -d "$d/data" ] && [ -d "$d/figures" ] || continue
    pass "experiment の 3 点セット ($d)"; return 0
  done
  fail "experiment: data/shared/experiments/*/README.md の見出し行に #$n を含み data/ と figures/ を伴うものが無い"
}

