#!/usr/bin/env bash
#
# 品質チェックの呼び出し（scripts/flow/lib.sh から source される）。
#
# ★ **lib.sh から切り出した**。lib.sh が 300 行の目安に達したため、
#   「段から scope を決めて、直前に通っていれば省く」という 1 つの責務をここへ移した。
#   単独では使わない。`$QUALITY` と `head2` / `say` は lib.sh が定義する。
#
# ★ `| grep -q` / `| head ` を使わない（pipefail 下の SIGPIPE）。

# ── 品質チェック（段から scope を決める。環境から継承しない）──────
# ★ `QUALITY_SCOPE=docs` はコード検査を丸ごと飛ばす
#   （scripts/quality-check.sh の QUALITY_SCOPE=docs の分岐）。継承すると
#   `QUALITY_SCOPE=docs bash scripts/flow/task-run.sh N` の 1 行で無害化される。
# ★ 文書の段でも、差分にコード（scripts/・tests/・*.sh・*.py）があれば全部を検査する。
#   git が失敗したら安全側（all）に倒す
scope_for() {
  case "$1" in survey|spec|docs) ;; *) printf 'all'; return;; esac
  local base mb files
  base="$(start_point_or_empty)"; [ -n "$base" ] || { printf 'all'; return; }
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || { printf 'all'; return; }
  files="$(git diff --name-only "$mb" 2>/dev/null)" || { printf 'all'; return; }
  files="$files
$(git ls-files --others --exclude-standard 2>/dev/null)" || { printf 'all'; return; }
  if [[ "$files" =~ (^|$'\n')(scripts/|tests/)|\.(sh|py)($|$'\n') ]]; then printf 'all'; else printf 'docs'; fi
}

# ★ 「直前に同じ内容で通った」かを見る述語。
#   記録は `HEAD scope QUALITY_FULL_SCAN` と走らせた quality-check.sh の hash。**全部一致したときだけ省く**
#   （全走査の指示で回した記録が無いのに、差分だけの記録で全走査を省かないため）。
#   **判定はここ 1 箇所。** 呼び出し側（issue-finish.sh / commit.sh）は run_quality を呼ぶだけ。
#   記録は .git/ の中に置く（worktree ごとに分かれ、git clean でも消えず、追跡対象にもならない）。
quality_record_key() {  # quality_record_key <scope> → 記録する 1 行
  printf '%s %s full=%s qc=%s' "$(git rev-parse HEAD 2>/dev/null)" "$1" "${QUALITY_FULL_SCAN:-0}" \
    "$(git hash-object "$QUALITY" 2>/dev/null)"
}
quality_record_matches() {  # quality_record_matches <scope>
  local scope="$1" f rec
  f="$(git rev-parse --git-dir 2>/dev/null)/flow-quality-passed" || return 1
  [ -f "$f" ] || return 1
  # 作業ツリーが dirty なら、コミットしていない変更が検査されていない
  local st; st="$(git status --porcelain)" || return 1  # ★ 失敗を「綺麗」と読まない
  [ -z "$st" ] || return 1
  rec="$(cat "$f" 2>/dev/null)" || return 1
  git rev-parse --verify --quiet HEAD >/dev/null || return 1
  # ★ scope も一致を要求する。docs で通った記録で all の段を省くと、
  #   コード検査（shellcheck / ruff / テスト）が丸ごと飛ぶ
  [ "$rec" = "$(quality_record_key "$scope")" ]
}

# ★ 直前の run_quality が実際に走ったか（1）省いたか（0）。issue の完了報告が
#   「通過」と書くか「省いた」と書くかに使う。**記録に嘘を書かないため**
# shellcheck disable=SC2034  # 参照は issue-finish.sh 側
QUALITY_RAN=0
run_quality() {
  local scope f; scope="$(scope_for "$1")"
  QUALITY_RAN=0
  if quality_record_matches "$scope"; then
    head2 "品質チェック（QUALITY_SCOPE=$scope）"
    # ★ **省いたことを黙らない**（「存在するようにしか見えない検査」を作らない）
    say "  --   直前に同じ内容で通っているので省いた（HEAD $(git rev-parse --short HEAD) / scope $scope / QUALITY_FULL_SCAN=${QUALITY_FULL_SCAN:-0}）"
    return 0
  fi
  head2 "品質チェック（QUALITY_SCOPE=$scope）"
  # ★ **quality-check.sh が読む環境変数を全部落とす**。
  #   `QUALITY_BASE_BRANCH=HEAD` を渡すと変更ファイルが空になり、
  #   **コミット済みの変更が shellcheck / ruff の対象から消える**（実測）。
  #   QUALITY_FULL_SCAN は落とさない（記録の鍵に入れてある）。
  env -u QUALITY_SCOPE -u QUALITY_BASE_BRANCH \
      QUALITY_SCOPE="$scope" bash "$QUALITY" \
    || die "品質チェックが落ちた。直してから再度呼ぶこと"
  # ★ 成功した直後だけ記録する（失敗した実行を「通った」と記録しない）
  f="$(git rev-parse --git-dir)/flow-quality-passed"
  printf '%s\n' "$(quality_record_key "$scope")" > "$f" 2>/dev/null || true
  # shellcheck disable=SC2034  # 参照は issue-finish.sh 側
  QUALITY_RAN=1
}

