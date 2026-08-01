#!/usr/bin/env bash
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
#   - **実行した検査と未実行の検査を最後に必ず列挙する**（#121）。
#     「失敗0件」と「実行0件」は違う。無言で切り捨てない
#
# 互換性:
#   macOS 標準の bash 3.2 で動く範囲に限定する（`mapfile` 等 bash 4+ 構文は使わない）。
#   `set -u` 下では空配列の `"${arr[@]}"` 展開自体がエラーになるため、
#   配列を展開する前に必ず `${#arr[@]}` で件数を確認する。
#
# 環境変数:
#   QUALITY_SCOPE=docs   コード検査をスキップ（survey / docs Issue 用）
#   QUALITY_SCOPE=all    既定。検出できた検査を全て実行
#
# プロジェクト固有の検査を追加する場合は「プロジェクト固有の検査」節に記述すること。

set -uo pipefail

FAILED=0
RAN_ANY=0

# 検査名の蓄積。bash 3.2 には連想配列も nameref も無いので改行区切り文字列で持つ
RAN_NAMES=""
FAILED_NAMES=""
NOTRUN_NAMES=""

append_ran() { RAN_NAMES="${RAN_NAMES}${RAN_NAMES:+$'\n'}$1"; }
append_failed() { FAILED_NAMES="${FAILED_NAMES}${FAILED_NAMES:+$'\n'}$1"; }
append_notrun() { NOTRUN_NAMES="${NOTRUN_NAMES}${NOTRUN_NAMES:+$'\n'}$1"; }

count_names() {
  [ -n "$1" ] || { echo 0; return 0; }
  printf '%s\n' "$1" | wc -l | tr -d ' '
}

join_names() {
  local out="" line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    out="${out}${out:+, }${line}"
  done <<EOF
$1
EOF
  printf '%s' "$out"
}

info() { echo ">>> $*"; }

# skip: 検査対象が存在しない / 意図的に対象外。失敗ではないが「未実行」として必ず列挙する
skip() { echo "--- skip: $*"; append_notrun "$*"; }

# warn_missing: 検査系そのものが導入されていない。skip とは意味が違うので関数を分ける（#121 D2/D4）。
#   「検査対象が無い」のと「検査系が入っていない」のは別事象で、後者は環境の不備。
#   ここで exit 1 にしないのは唯一の Fallback（ホスト環境で完了ゲートが常時閉じるのを避ける）。
#   その代わり (a) 警告を出す (b) 未実行として必ず列挙する (c) RAN_ANY に数えない、
#   そして backstop として .github/workflows/quality.yml の CI が必ず検査する。
warn_missing() {
  echo "!!! WARNING: $* — 検査系が未導入のため実行できません"
  append_notrun "⚠ $*"
}

run_check() {
  # run_check <表示名> <コマンド...>
  local name="$1"; shift
  info "$name"
  RAN_ANY=1
  if "$@"; then
    append_ran "$name"
  else
    echo "!!! FAILED: $name"
    FAILED=1
    append_failed "$name"
  fi
}

echo "=== Running quality checks ==="

SCOPE="${QUALITY_SCOPE:-all}"
echo "scope: $SCOPE"

# ---------------------------------------------------------------------------
# Python (uv + ruff + mypy + pytest)
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "docs" ]; then
  skip "Python 検査（QUALITY_SCOPE=docs）"
else
  # 検査対象ディレクトリ。scripts/qa はテンプレート同梱の Python コード（#121 D3）
  PY_TARGETS=()
  for d in src tests scripts/qa; do
    if [ -d "$d" ]; then PY_TARGETS+=("$d"); fi
  done

  if [ ! -f pyproject.toml ]; then
    # pyproject.toml が無いプロジェクト（テンプレート自身もこれ）。
    # uv による環境構築はできないが、ruff 単体があれば構文と未定義名だけは検査できる。
    if [ ${#PY_TARGETS[@]} -eq 0 ]; then
      skip "Python 検査（pyproject.toml も Python ディレクトリも無い）"
    elif ! command -v ruff >/dev/null 2>&1; then
      warn_missing "Python 検査（pyproject.toml が無く ruff も未インストール）"
    else
      # 設定ファイルが無い前提なので --isolated。
      # ruff の既定ルールセットはバージョン更新で増えるため、
      # 完了ゲートが勝手に赤くならないよう安定した E9（構文）/ F（pyflakes）に固定する。
      run_check "ruff check (standalone: E9,F / ${#PY_TARGETS[@]} dirs)" \
        ruff check --isolated --select E9,F "${PY_TARGETS[@]}"
    fi
    skip "mypy / pytest（pyproject.toml が無い）"
  elif ! command -v uv >/dev/null 2>&1; then
    echo "!!! pyproject.toml があるが uv が見つからない"
    FAILED=1
    append_failed "Python 検査（pyproject.toml があるが uv が無い）"
  else
    info "uv sync --all-extras (first run may take time)"
    if ! uv sync --all-extras --quiet; then
      echo "!!! FAILED: uv sync"
      FAILED=1
      append_failed "uv sync"
    else
      if [ ${#PY_TARGETS[@]} -eq 0 ]; then
        skip "ruff / mypy（src/ tests/ scripts/qa/ のいずれも無い）"
      else
        run_check "ruff check" uv run ruff check "${PY_TARGETS[@]}"
        run_check "ruff format --check" uv run ruff format --check "${PY_TARGETS[@]}"
        if [ -d src ]; then
          run_check "mypy" uv run mypy src/
        else
          skip "mypy（src/ が無い）"
        fi
      fi

      if [ -d tests ] || grep -q "\[tool.pytest" pyproject.toml 2>/dev/null; then
        run_check "pytest" uv run pytest
      else
        skip "pytest（tests/ も pytest 設定も無い）"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Shell script
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "docs" ]; then
  skip "shellcheck（QUALITY_SCOPE=docs）"
elif ! command -v shellcheck >/dev/null 2>&1; then
  warn_missing "shellcheck（未インストール）"
else
  SH_FILES=()
  while IFS= read -r f; do
    [ -n "$f" ] && SH_FILES+=("$f")
  done < <(git ls-files '*.sh' 2>/dev/null)

  # 拡張子を持たないシェルスクリプト（例: claude-san）は `*.sh` に一致しないため
  # shebang で拾う（#121 D3）。`*.sh` 既収集分は除外して二重検査を避ける。
  # 判定は shellcheck が解釈できる sh/bash/dash/ksh のみ。
  # `#!/usr/bin/env python3` や `#!/usr/bin/env zsh` は対象外にする
  # （zsh は shellcheck が非対応で、含めると検査自体が落ちる）。
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *.sh) continue ;; esac
    [ -f "$f" ] || continue
    if head -n 1 "$f" 2>/dev/null \
      | LC_ALL=C grep -Eq '^#![[:space:]]*[^[:space:]]*/(env[[:space:]]+)?(ba|da|k)?sh([[:space:]]|$)'; then
      SH_FILES+=("$f")
    fi
  done < <(git ls-files 2>/dev/null)

  if [ ${#SH_FILES[@]} -eq 0 ]; then
    skip "shellcheck（対象ファイル無し）"
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
#   実行/失敗/未実行を必ず列挙する。無言の切り捨てはしない（#121 D4）
# ---------------------------------------------------------------------------
RAN_N=$(count_names "$RAN_NAMES")
FAILED_N=$(count_names "$FAILED_NAMES")
NOTRUN_N=$(count_names "$NOTRUN_NAMES")

print_summary() {
  if [ "$RAN_N" -gt 0 ]; then
    echo "  実行 (${RAN_N}件): $(join_names "$RAN_NAMES")"
  else
    echo "  実行 (0件): なし"
  fi
  if [ "$FAILED_N" -gt 0 ]; then
    echo "  失敗 (${FAILED_N}件): $(join_names "$FAILED_NAMES")"
  fi
  if [ "$NOTRUN_N" -gt 0 ]; then
    echo "  未実行 (${NOTRUN_N}件): $(join_names "$NOTRUN_NAMES")"
    case "$NOTRUN_NAMES" in
      *"⚠"*)
        echo "    ※ ⚠ 印は「検査系が未導入」。CI（.github/workflows/quality.yml）側では実行されます"
        ;;
    esac
  fi
}

if [ "$FAILED" -ne 0 ]; then
  echo "=== Quality checks FAILED ==="
  print_summary
  exit 1
fi

if [ "$RAN_ANY" -eq 0 ]; then
  echo "=== 実行対象の検査がありませんでした（このリポジトリには該当する検査対象が無い） ==="
  print_summary
  exit 0
fi

if [ "$NOTRUN_N" -gt 0 ]; then
  echo "=== All quality checks passed（未実行あり: ${NOTRUN_N}件） ==="
else
  echo "=== All quality checks passed ==="
fi
print_summary
exit 0
