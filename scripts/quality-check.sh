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
#   - **ファイル単位で完結する検査は変更ファイルに限定する**（#135）。
#     全件走査だと「そのファイルを1行も触っていない PR」が既存の指摘で落ちる
#
# 検査範囲（#135）:
#   既定は「変更ファイルのみ」。限定するのは shellcheck と ruff だけで、
#   横断的な整合性検査（MANIFEST / スキル参照 / スキルラベル）・pytest・mypy は全件のまま。
#   ★ トレードオフ: **その変更で触っていない既存の指摘は既定モードでは検出されない。**
#   全件の健全性確認は `QUALITY_FULL_SCAN=1 bash scripts/quality-check.sh` を
#   定期的に（例: main への取り込み後や週次で）実行して行うこと。
#
# 互換性:
#   macOS 標準の bash 3.2 で動く範囲に限定する（`mapfile` 等 bash 4+ 構文は使わない）。
#   `set -u` 下では空配列の `"${arr[@]}"` 展開自体がエラーになるため、
#   配列を展開する前に必ず `${#arr[@]}` で件数を確認する。
#
# 環境変数:
#   QUALITY_SCOPE=docs        コード検査をスキップ（survey / docs Issue 用）
#   QUALITY_SCOPE=all         既定。検出できた検査を全て実行
#   QUALITY_FULL_SCAN=1       ファイル単位の検査をツリー全件に戻す（既定は変更ファイル限定）
#   QUALITY_BASE_BRANCH=<ref> 差分の基点を明示する。**無効な値なら黙って既定に落とさず失敗する**
#
#   ★ QUALITY_SCOPE と QUALITY_FULL_SCAN は別の軸（#135 D4）。
#     前者は「どの種類の検査を回すか」、後者は「どの範囲のファイルを見るか」。
#     1つの変数に2つの意味を持たせない。
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
#   その代わり (a) 警告を出す (b) 未実行として必ず列挙する (c) RAN_ANY に数えない。
#   **backstop は devcontainer**（.devcontainer/Dockerfile が shellcheck を導入する）。
#   本テンプレートの標準作業環境は devcontainer であり、そこでは必ず検査が走る。
#   ホストで作業する場合は検査が走らないことがあるので、下のサマリで必ず確認すること。
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

# ---------------------------------------------------------------------------
# 検査範囲の決定（#135）
# ---------------------------------------------------------------------------
SCOPE_MODE=full        # full | changed。既定値は安全側（全件）にしておく
BASE_REF=""
CHANGED_FILES=""
SCOPE_FALLBACK_REASON=""

# resolve_base_ref: 差分の基点を決める（#135 D1）
#   QUALITY_BASE_BRANCH → origin/HEAD から検出した既定ブランチ → main
#
#   ★ #122 D4（既定ブランチは main 固定）との関係:
#     本テンプレートの規約は「既定ブランチは main」であり、`origin/HEAD` からの検出は
#     #122 で**採らなかった**方針である。ここで検出しているのは
#     「派生プロジェクトが別名を使っていても diff の基点だけは当たる」ための**保険**であり、
#     検出できなければ必ず `main` に落ちる。**規約そのものを緩めるものではない。**
#     用途が読み取り専用（diff の基点選択）で、外しても検査範囲が広がる/狭まるだけであり、
#     ブランチ切替やマージ後処理のような破壊的操作を伴わないことが差分の根拠。
#
#   戻り値: 0=解決した / 1=検出できない（全件へフォールバック） / 2=明示指定が無効（失敗させる）
resolve_base_ref() {
  local cand default_branch
  if [ -n "${QUALITY_BASE_BRANCH:-}" ]; then
    # 明示指定は最優先。無効なら黙って既定に落とさない（利用者の指定を握り潰さない）
    if git rev-parse --verify --quiet "$QUALITY_BASE_BRANCH" >/dev/null 2>&1; then
      BASE_REF="$QUALITY_BASE_BRANCH"
      return 0
    fi
    return 2
  fi
  default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [ -n "$default_branch" ] || default_branch=main
  for cand in "origin/$default_branch" "$default_branch"; do
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      BASE_REF="$cand"
      return 0
    fi
  done
  SCOPE_FALLBACK_REASON="base ref を解決できない（origin/$default_branch も $default_branch も存在しない）"
  return 1
}

# scope_setup: SCOPE_MODE / BASE_REF / CHANGED_FILES を決めて範囲を表示する（#135 D2/D5）
#
#   変更ファイル = merge-base からの差分 ＋ 未コミットの変更 ＋ 未追跡ファイル。
#   削除されたファイルは `--diff-filter=d` で除く（存在しないファイルを渡すと検査が落ちるため）。
#
#   ★ main 上で実行すると merge-base が HEAD 自身になるので**差分は空**になり、
#     未コミット分しか検査されない。main での定期的な健全性確認は QUALITY_FULL_SCAN=1 を使うこと。
#
#   ★ base が解決できない場合は**全件走査にフォールバックする**（新規リポジトリ・shallow clone）。
#     PR #129 は即 FAIL としていたが、main が本当に無いリポジトリで完了ゲートが恒久的に
#     赤くなる（RED の常態化）ため意図的に逸脱する。全件走査は限定走査の厳密な上位集合なので
#     検出漏れ方向の silent-wrong を生まない。**ただし理由は必ず表示する。**
scope_setup() {
  local rc mb changed_n
  if [ "${QUALITY_FULL_SCAN:-}" = "1" ]; then
    SCOPE_MODE=full
    echo "対象範囲: 全件走査（QUALITY_FULL_SCAN=1）"
    return 0
  fi

  resolve_base_ref
  rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "!!! FAILED: QUALITY_BASE_BRANCH='${QUALITY_BASE_BRANCH:-}' を解決できません"
    FAILED=1
    append_failed "base ref の解決（QUALITY_BASE_BRANCH が無効）"
    SCOPE_MODE=full
    echo "対象範囲: 全件走査（base を確定できないため安全側に倒す）"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    SCOPE_MODE=full
    echo "対象範囲: 全件走査へフォールバック（理由: ${SCOPE_FALLBACK_REASON}）"
    echo "    基点を明示するには QUALITY_BASE_BRANCH=<ref> を指定してください"
    return 0
  fi

  mb="$(git merge-base HEAD "$BASE_REF" 2>/dev/null)"
  if [ -z "$mb" ]; then
    SCOPE_MODE=full
    SCOPE_FALLBACK_REASON="HEAD と $BASE_REF の merge-base が取れない（shallow clone / 履歴が非共有）"
    echo "対象範囲: 全件走査へフォールバック（理由: ${SCOPE_FALLBACK_REASON}）"
    return 0
  fi

  CHANGED_FILES="$(
    {
      git diff --name-only --diff-filter=d "$mb" HEAD
      git diff --name-only --diff-filter=d HEAD
      git ls-files --others --exclude-standard
    } 2>/dev/null | sort -u
  )"
  SCOPE_MODE=changed
  changed_n="$(count_names "$CHANGED_FILES")"
  echo "base: $BASE_REF (merge-base ${mb:0:12})"
  echo "対象範囲: 変更ファイルのみ ${changed_n} 件（shellcheck / ruff）— 全件は QUALITY_FULL_SCAN=1"
}

echo "=== Running quality checks ==="

SCOPE="${QUALITY_SCOPE:-all}"
echo "scope: $SCOPE"

# QUALITY_SCOPE=docs のときはファイル単位の検査自体が走らないので、
# 範囲計算もフォールバック表示もしない（無意味なノイズになる。#135 D4）
if [ "$SCOPE" != "docs" ]; then
  scope_setup
fi

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

  # ruff の対象を決める（#135 D3）。変更ファイル限定モードでは
  # 「PY_TARGETS 配下の変更された *.py」だけに絞る。
  RUFF_TARGETS=()
  RUFF_LABEL="${#PY_TARGETS[@]} dirs, 全件"
  if [ ${#PY_TARGETS[@]} -gt 0 ]; then
    if [ "$SCOPE_MODE" = "changed" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        case "$f" in *.py) ;; *) continue ;; esac
        for d in "${PY_TARGETS[@]}"; do
          case "$f" in "$d"/*) RUFF_TARGETS+=("$f"); break ;; esac
        done
      done <<EOF
$CHANGED_FILES
EOF
      RUFF_LABEL="${#RUFF_TARGETS[@]} files, 変更ファイルのみ"
    else
      RUFF_TARGETS=("${PY_TARGETS[@]}")
    fi
  fi

  if [ ! -f pyproject.toml ]; then
    # pyproject.toml が無いプロジェクト（テンプレート自身もこれ）。
    # uv による環境構築はできないが、ruff 単体があれば構文と未定義名だけは検査できる。
    if [ ${#PY_TARGETS[@]} -eq 0 ]; then
      skip "Python 検査（pyproject.toml も Python ディレクトリも無い）"
    elif [ ${#RUFF_TARGETS[@]} -eq 0 ]; then
      skip "ruff（変更された Python ファイルが無い）"
    elif ! command -v ruff >/dev/null 2>&1; then
      warn_missing "Python 検査（pyproject.toml が無く ruff も未インストール）"
    else
      # 設定ファイルが無い前提なので --isolated。
      # ruff の既定ルールセットはバージョン更新で増えるため、
      # 完了ゲートが勝手に赤くならないよう安定した E9（構文）/ F（pyflakes）に固定する。
      run_check "ruff check (standalone: E9,F / ${RUFF_LABEL})" \
        ruff check --isolated --select E9,F "${RUFF_TARGETS[@]}"
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
        if [ ${#RUFF_TARGETS[@]} -eq 0 ]; then
          skip "ruff（変更された Python ファイルが無い）"
        else
          run_check "ruff check (${RUFF_LABEL})" uv run ruff check "${RUFF_TARGETS[@]}"
          run_check "ruff format --check (${RUFF_LABEL})" uv run ruff format --check "${RUFF_TARGETS[@]}"
        fi
        if [ -d src ]; then
          # ★ mypy は変更ファイルに限定しない（#135 D3 警告1）。
          #   型エラーは**ファイル間を伝播する**: シグネチャを変えると未変更の呼び出し側が壊れ、
          #   既定の follow-imports は未変更ファイルのエラーも報告する。
          #   ファイル単位で完結する検査（shellcheck / ruff）とは同型に扱えない。
          #   ※ コメント行を "# shellcheck" で始めないこと。shellcheck ディレクティブと
          #     解釈されて SC1073（parse error）になる。
          run_check "mypy" uv run mypy src/
        else
          skip "mypy（src/ が無い）"
        fi
      fi

      # pytest も限定しない（テスト全体を回すのが本来の目的）
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

# collect_sh_files: 標準入力のファイル一覧から shellcheck 対象を選ぶ。
#   **対象判定の単一情報源**（#121 D3 の収集ルール）:
#     - 拡張子 `*.sh`
#     - 拡張子を持たなくても shebang が sh/bash/dash/ksh のもの（例: claude-san）
#       `#!/usr/bin/env python3` や `#!/usr/bin/env zsh` は対象外
#       （zsh は shellcheck が非対応で、含めると検査自体が落ちる）
#
#   全件走査では追跡ファイル一覧を、限定走査では変更ファイル一覧を流し込む。
#   ★ 限定を「拡張子マッチ」で書き直さないこと（#135 D3 警告2）。
#     `*.sh` だけで絞ると claude-san のような拡張子なしスクリプトが素通りする。
#     ルールを1箇所に置き、流し込む集合だけを変えることで両モードの判定を一致させる。
collect_sh_files() {
  local f
  SH_FILES=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # 削除済み・未生成のパスは渡さない（shellcheck が file-not-found で落ちるため）
    [ -f "$f" ] || continue
    case "$f" in
      *.sh) SH_FILES+=("$f"); continue ;;
    esac
    if head -n 1 "$f" 2>/dev/null \
      | LC_ALL=C grep -Eq '^#![[:space:]]*[^[:space:]]*/(env[[:space:]]+)?(ba|da|k)?sh([[:space:]]|$)'; then
      SH_FILES+=("$f")
    fi
  done
}

if [ "$SCOPE" = "docs" ]; then
  skip "shellcheck（QUALITY_SCOPE=docs）"
elif ! command -v shellcheck >/dev/null 2>&1; then
  warn_missing "shellcheck（未インストール）"
else
  SH_FILES=()
  SH_LABEL="全件"
  if [ "$SCOPE_MODE" = "changed" ]; then
    SH_LABEL="変更ファイルのみ"
    collect_sh_files <<EOF
$CHANGED_FILES
EOF
  else
    # 全件走査でも未追跡ファイル（gitignore 対象は除く）を含める。
    # 含めないと**限定走査の厳密な上位集合にならず**、base 解決不能時のフォールバックで
    # 「未追跡の新規スクリプトだけが検査されない」という検出漏れが生じる（#135 Fallback の前提）。
    collect_sh_files < <(git ls-files --cached --others --exclude-standard 2>/dev/null)
  fi

  if [ ${#SH_FILES[@]} -eq 0 ]; then
    if [ "$SCOPE_MODE" = "changed" ]; then
      skip "shellcheck（変更されたシェルスクリプトが無い vs ${BASE_REF:-?}）"
    else
      skip "shellcheck（対象ファイル無し）"
    fi
  else
    run_check "shellcheck (${#SH_FILES[@]} files, ${SH_LABEL})" shellcheck "${SH_FILES[@]}"
    if [ "$SCOPE_MODE" = "changed" ]; then
      echo "    （変更された ${#SH_FILES[@]} 件のみ検査。ツリーの残りは未検査 — 全件は QUALITY_FULL_SCAN=1）"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# プロジェクト固有の検査
# ---------------------------------------------------------------------------
# 例:
#   run_check "custom lint" ./scripts/my-lint.sh
#
# ★ 以降の検査は**変更ファイルに限定しない**（#135 D3）。
#   いずれもリポジトリ全体の整合性（グラフ的性質）が対象で、変更ファイルだけを見ると
#   検出原理が壊れる。例: スキルを1つ削除したとき、それを参照している側のファイルは
#   変更されていないので、限定すると参照切れを永久に検出できない。

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

# quality-check 自身の検査範囲の回帰テスト（#135 D6）
#   「限定が壊れて全件走査に戻る」「限定しすぎて検出漏れになる」のどちらも
#   通常運用では気づけず、下流でしか顕在化しない。ゲート自身で pin する
#   （#117 / #118 と同じ再発防止の型）。1〜2秒で終わる。
if [ "$SCOPE" = "docs" ]; then
  skip "検査範囲の回帰テスト（QUALITY_SCOPE=docs）"
elif [ ! -f tests/test_quality_check_scope.sh ]; then
  skip "検査範囲の回帰テスト（tests/test_quality_check_scope.sh が無い）"
else
  run_check "検査範囲の回帰テスト" bash tests/test_quality_check_scope.sh --quiet
fi

# devcontainer の PID 1 が init（tini）であること（由来: delta-clip-dev #165）
#   PID 1 が sleep のままだと孤児プロセスを reap できず、shutdownAction: none と
#   相まってゾンビが際限なく溜まる（実測: 連続稼働 5 日で 246 プロセス中 217 ゾンビ、
#   VS Code が接続不能）。/template-sync は .devcontainer/ を「差分表示→選択適用」で
#   扱うため init: true が巻き戻る経路が実在する。静的に pin して守る。
#   docker compose config はローカル解析のみで daemon を必要としない。
#
#   ★ docker compose が無い場合は skip ではなく warn_missing。巻き戻しを起こす
#     /template-sync は人がホストで回すことがあり、そこで黙って pin が外れると
#     この検査の意味が無くなる（skip と warn_missing の使い分けは上の定義を参照）。
if [ "$SCOPE" = "docs" ]; then
  skip "devcontainer init チェック（QUALITY_SCOPE=docs）"
elif [ ! -f .devcontainer/docker-compose.yml ]; then
  skip "devcontainer init チェック（.devcontainer/docker-compose.yml が無い）"
elif [ ! -f tests/test_devcontainer_init.sh ]; then
  warn_missing "devcontainer init チェック（tests/test_devcontainer_init.sh が無い）"
elif ! docker compose version >/dev/null 2>&1; then
  warn_missing "devcontainer init チェック（docker compose が使えない）"
else
  run_check "devcontainer init: true" bash tests/test_devcontainer_init.sh
fi

# worktree の相対パス設定ゲートの回帰テスト（由来: delta-clip-dev #167）
#   ゲートが緩むと、片側だけ git 2.48 以降の環境で worktree の登録が消える／
#   古い側の git が全コマンド fatal になる。どちらも通常運用では気づけない。
if [ "$SCOPE" = "docs" ]; then
  skip "worktree 相対パス設定の回帰テスト（QUALITY_SCOPE=docs）"
elif [ ! -f scripts/configure-worktree-paths.sh ]; then
  skip "worktree 相対パス設定の回帰テスト（scripts/configure-worktree-paths.sh が無い）"
elif [ ! -f tests/test_configure_worktree_paths.sh ]; then
  warn_missing "worktree 相対パス設定の回帰テスト（tests/test_configure_worktree_paths.sh が無い）"
else
  run_check "worktree 相対パス設定のゲート" bash tests/test_configure_worktree_paths.sh
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
        echo "    ※ ⚠ 印は「検査系が未導入」。devcontainer 内では導入済みなので、"
        echo "      ホストで作業している場合は devcontainer で再実行するか、手元に導入してください"
        ;;
    esac
  fi
  if [ "$SCOPE_MODE" = "changed" ]; then
    echo "  範囲: 変更ファイルのみ（base: ${BASE_REF}）。触っていないファイルの既存指摘は"
    echo "        検出されません。全件は QUALITY_FULL_SCAN=1 で確認してください"
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
