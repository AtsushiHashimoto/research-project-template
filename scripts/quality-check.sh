#!/bin/bash
# Quality check script for the project
# Called by /commit-merge and /task-run workflows
#
# Exit codes:
#   0: All checks passed (or no applicable checks found)
#   1: One or more checks failed
#
# 設計方針:
#   - プロジェクトの構成を検出し、該当する検査だけを実行する
#   - 検査対象が存在しないこと自体は失敗ではない（Markdown のみのリポジトリ等）
#   - 実際の検査が落ちた場合のみ失敗させる
#
# 環境変数:
#   QUALITY_SCOPE=docs   コード検査をスキップ（survey / docs Issue 用）
#   QUALITY_SCOPE=all    既定。検出できた検査を全て実行
#
# プロジェクト固有の検査を追加する場合は「プロジェクト固有の検査」節に記述すること。

set -uo pipefail

FAILED=0
RAN_ANY=0

info() { echo ">>> $*"; }
skip() { echo "--- skip: $*"; }

run_check() {
  # run_check <表示名> <コマンド...>
  local name="$1"; shift
  info "$name"
  if "$@"; then
    RAN_ANY=1
  else
    echo "!!! FAILED: $name"
    FAILED=1
    RAN_ANY=1
  fi
}

# 変更ファイルの解決（#142 / #153）
#   ツリー全体を検査すると、そのファイルを1行も触っていない PR が既存の指摘で落ちる。
#   これは #105 が changed-file 判定から取り除いたのと同じ誤検出なので、
#   ファイル単位の検査は base ref との差分に限定する。
#   base は origin/<既定> -> ローカル<既定> の順で実在するものを採る。
#   どちらも解決できないなら「検査が走らなかった」ことを明示して止める（PASS にしない）。
BASE_REF=""
CHANGED_FILES=""

resolve_base_ref() {
  local cand
  if [ -n "${QUALITY_BASE_BRANCH:-}" ]; then
    git rev-parse --verify --quiet "$QUALITY_BASE_BRANCH" >/dev/null && {
      BASE_REF="$QUALITY_BASE_BRANCH"; return 0; }
    return 1
  fi
  local default_branch
  default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [ -n "$default_branch" ] || default_branch=main
  for cand in "origin/$default_branch" "$default_branch"; do
    if git rev-parse --verify --quiet "$cand" >/dev/null; then BASE_REF="$cand"; return 0; fi
  done
  return 1
}

compute_changed_files() {
  local base
  resolve_base_ref || return 1
  base="$(git merge-base HEAD "$BASE_REF" 2>/dev/null)" || return 1
  CHANGED_FILES="$(git diff --name-only --diff-filter=d "$base" HEAD 2>/dev/null; git diff --name-only --diff-filter=d HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)" || return 1
  CHANGED_FILES="$(printf '%s\n' "$CHANGED_FILES" | sort -u)"
  return 0
}

# changed_of <拡張子> -> 変更された該当ファイルを1行1件で返す
changed_of() {
  printf '%s\n' "$CHANGED_FILES" | grep -E "\\.$1\$" || true
}

echo "=== Running quality checks ==="

SCOPE="${QUALITY_SCOPE:-all}"
echo "scope: $SCOPE"

if [ "$SCOPE" != "docs" ]; then
  if compute_changed_files; then
    echo "base: $BASE_REF（ファイル単位の検査は変更分のみ）"
  else
    echo "!!! FAILED: base ref を解決できず変更ファイルを特定できない（検査が走らなかったことは PASS ではない）"
    FAILED=1
  fi
fi

# ---------------------------------------------------------------------------
# Python (uv + ruff + mypy + pytest)
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "docs" ]; then
  skip "Python checks (QUALITY_SCOPE=docs)"
elif [ ! -f pyproject.toml ]; then
  skip "Python checks (pyproject.toml が無い)"
elif ! command -v uv >/dev/null 2>&1; then
  echo "!!! pyproject.toml があるが uv が見つからない"
  FAILED=1
else
  info "uv sync --all-extras (first run may take time)"
  if ! uv sync --all-extras --quiet; then
    echo "!!! FAILED: uv sync"
    FAILED=1
  else
    # 検査対象ディレクトリを決定
    TARGETS=()
    for d in src tests; do
      [ -d "$d" ] && TARGETS+=("$d")
    done
    if [ ${#TARGETS[@]} -eq 0 ]; then
      skip "ruff / mypy (src/ も tests/ も無い)"
    else
      run_check "ruff check" uv run ruff check "${TARGETS[@]}"
      run_check "ruff format --check" uv run ruff format --check "${TARGETS[@]}"
      [ -d src ] && run_check "mypy" uv run mypy src/
    fi

    if [ -d tests ] || grep -q "\[tool.pytest" pyproject.toml 2>/dev/null; then
      run_check "pytest" uv run pytest
    else
      skip "pytest (tests/ も pytest 設定も無い)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Shell script
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "docs" ]; then
  skip "shellcheck (QUALITY_SCOPE=docs)"
elif ! command -v shellcheck >/dev/null 2>&1; then
  skip "shellcheck (未インストール)"
else
  mapfile -t SH_FILES < <(changed_of sh)
  if [ ${#SH_FILES[@]} -eq 0 ]; then
    skip "shellcheck (変更された *.sh が無い vs $BASE_REF)"
  else
    # -x/--source-path: sourced lib を「呼び出し元の CWD」ではなくスクリプト自身の
    # ディレクトリから解決する。単体検査にすると SC1091 が必ず出るため必須。
    run_check "shellcheck (${#SH_FILES[@]} changed)" \
      shellcheck -x --source-path=SCRIPTDIR "${SH_FILES[@]}"
    echo "    （変更された ${#SH_FILES[@]} 件のみ検査。ツリーの残りは未検査）"
  fi
fi

# ---------------------------------------------------------------------------
# プロジェクト固有の検査
# ---------------------------------------------------------------------------
# 例:
#   run_check "custom lint" ./scripts/my-lint.sh

# .claude/rules/template/MANIFEST.sha256 の整合
#   MANIFEST がずれていると /template-sync が無改変のルールを「還流候補」として
#   退避し続ける（＝改変検出が機能しない）。ルールを編集したら再生成が必要。
if [ ! -d .claude/rules/template ]; then
  skip "rules MANIFEST 整合チェック（.claude/rules/template/ が無い）"
elif [ ! -f scripts/generate-rules-manifest.sh ]; then
  skip "rules MANIFEST 整合チェック（scripts/generate-rules-manifest.sh が無い）"
else
  run_check "rules MANIFEST 整合" bash scripts/generate-rules-manifest.sh --check
fi

# スキル参照名の実在検証
#   スキルのリネーム時に参照側が追従せず、実行経路が死んでいた事故への再発防止（#117）
if [ ! -d .claude/skills ]; then
  skip "スキル参照名の実在検証（.claude/skills/ が無い）"
elif [ ! -f scripts/check-skill-references.sh ]; then
  skip "スキル参照名の実在検証（scripts/check-skill-references.sh が無い）"
else
  run_check "スキル参照名の実在" bash scripts/check-skill-references.sh
fi

# スキルが使うラベルの定義済み検証
#   未定義ラベルを渡すと gh が 422 で失敗し、当該ステップが必ず落ちる（#118）
if [ ! -d .claude/skills ]; then
  skip "スキルのラベル定義検証（.claude/skills/ が無い）"
elif [ ! -f scripts/check-skill-labels.sh ]; then
  skip "スキルのラベル定義検証（scripts/check-skill-labels.sh が無い）"
else
  run_check "スキルのラベル定義" bash scripts/check-skill-labels.sh
fi

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
  echo "=== Quality checks FAILED ==="
  exit 1
fi

if [ "$RAN_ANY" -eq 0 ]; then
  echo "=== 実行対象の検査がありませんでした（このリポジトリには該当する検査対象が無い） ==="
else
  echo "=== All quality checks passed ==="
fi
exit 0
