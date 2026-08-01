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

echo "=== Running quality checks ==="

SCOPE="${QUALITY_SCOPE:-all}"
echo "scope: $SCOPE"

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
  mapfile -t SH_FILES < <(git ls-files '*.sh' 2>/dev/null)
  if [ ${#SH_FILES[@]} -eq 0 ]; then
    skip "shellcheck (対象ファイル無し)"
  else
    run_check "shellcheck (${#SH_FILES[@]} files)" shellcheck "${SH_FILES[@]}"
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
