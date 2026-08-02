#!/usr/bin/env bash
# ============================================================
# .spec/*.md の既定節の同期（/template-sync の .spec 処理の実体）
# [Template] research-project-template 由来
# ============================================================
#
# 対象: .spec/core-rules.md / invariants.md / known-issues.md
#
# 差し替える領域（仕様 #100 D2）:
#   `^# 既定の` の行から `^# プロジェクト固有` の**直前**まで。
#   `# プロジェクト固有` 以降（プロジェクト固有節）は**一切触らない**。
#
# 動作:
#   1. テンプレート側3ファイルの既定節を先に検証する（壊れていたら無変更で異常終了）
#   2. プロジェクト側の既定節をテンプレート側の内容で置き換える
#   3. R2: 固有節の**後ろ**に旧「## auto-reviewer への指示」節が残っている場合、
#      新しい既定節に同じ節が含まれるときに限り、旧節を除去する
#   4. マーカーが見つからないファイルは**スキップし、サマリに明示して非0 exit**
#
# 冪等: 同一テンプレートに対して2回実行すると2回目の変更は0件になる。
#
# Usage:
#   bash scripts/sync-spec-defaults.sh --source <template-checkout-dir> [options]
#   bash scripts/sync-spec-defaults.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=spec-defaults-common.sh
. "$SCRIPT_DIR/spec-defaults-common.sh"

usage() {
  cat <<'EOF'
.spec/*.md の既定節をテンプレートの最新版に差し替える。
「# プロジェクト固有」以降のプロジェクト固有節には触らない。

Usage:
  bash scripts/sync-spec-defaults.sh --source <template-checkout-dir> [options]

Options:
  --source <dir>        必須。テンプレートを clone / 展開したディレクトリ。
                        <dir>/.spec/*.md を取り込む
  --project-root <dir>  取り込み先。既定はカレントの git リポジトリルート
  --dry-run             何も変更せず、実行される処理だけを表示する
  -h, --help            この使い方を表示する

対象ファイル:
  .spec/core-rules.md / .spec/invariants.md / .spec/known-issues.md

Exit codes:
  0  全ファイルの同期に成功（変更なしを含む）
  1  失敗、またはマーカー不在でスキップしたファイルがある
  2  引数エラー

Example:
  TMP_DIR=$(mktemp -d)
  # テンプレートの URL は scripts/template-source.sh が単一情報源（ハードコードしない）
  git clone --depth 1 "$(bash scripts/template-source.sh)" "$TMP_DIR/template" || exit 1
  bash scripts/sync-spec-defaults.sh --source "$TMP_DIR/template"
EOF
}

# ---------------------------------------------------------------------------
# 引数
# ---------------------------------------------------------------------------
SOURCE_DIR=""
PROJECT_ROOT=""
DRY_RUN=false

if [ $# -eq 0 ]; then
  # 引数なしでの誤爆防止: 既定値で暗黙に走らせない
  echo "ERROR: --source が指定されていません（引数なしでは実行しません）" >&2
  echo >&2
  usage >&2
  exit 2
fi

need_value() {
  # need_value <option> <value>
  if [ -z "$2" ]; then
    echo "ERROR: $1 には値が必要です" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      need_value "$1" "${2:-}"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --project-root)
      need_value "$1" "${2:-}"
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      echo >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$SOURCE_DIR" ]; then
  echo "ERROR: --source は必須です" >&2
  exit 2
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

SRC_SPEC="$SOURCE_DIR/.spec"
DST_SPEC="$PROJECT_ROOT/.spec"

# ---------------------------------------------------------------------------
# 事前チェック（ここで失敗する場合は作業ツリーを一切変更しない）
# ---------------------------------------------------------------------------
if [ ! -d "$SRC_SPEC" ]; then
  echo "ERROR: テンプレートの取得に失敗しています（.spec/ が見つかりません）" >&2
  echo "  探した場所: $SRC_SPEC" >&2
  echo "  clone が失敗していないか、--source の指定が正しいかを確認してください。" >&2
  echo "  何も変更していません。" >&2
  exit 1
fi

for name in "${SPEC_DEFAULT_FILES[@]}"; do
  if [ ! -f "$SRC_SPEC/$name" ]; then
    echo "ERROR: テンプレート側に $name がありません: $SRC_SPEC/$name" >&2
    echo "  取得が不完全な可能性があります。何も変更していません。" >&2
    exit 1
  fi
  if ! spec_bounds "$SRC_SPEC/$name" >/dev/null; then
    echo "ERROR: テンプレート側の $name に既定節のマーカーがありません" >&2
    echo "  必要なマーカー: '# 既定の...' と、その後ろの '# プロジェクト固有...'" >&2
    echo "  何も変更していません。" >&2
    exit 1
  fi
done

echo "=== .spec 既定節の同期 ==="
echo "  from: $SRC_SPEC"
echo "  to  : $DST_SPEC"
$DRY_RUN && echo "  mode: dry-run（変更しません）"

# ---------------------------------------------------------------------------
# 内部関数
# ---------------------------------------------------------------------------

# strip_old_autoreviewer <file> → 旧「## auto-reviewer への指示」節を除いた内容を stdout
#   見出し行から、次の見出し（^#）または EOF までを落とす。
strip_old_autoreviewer() {
  awk -v re="$SPEC_AUTOREVIEWER_RE" '
    $0 ~ re { skip = 1; next }
    skip == 1 { if ($0 ~ /^#/) { skip = 0 } else { next } }
    { print }
  ' "$1"
}

# extract_old_autoreviewer <file> → strip の逆。該当節のみを stdout（退避用）
extract_old_autoreviewer() {
  awk -v re="$SPEC_AUTOREVIEWER_RE" '
    $0 ~ re { keep = 1 }
    keep == 1 { if ($0 ~ /^#/ && $0 !~ re) { exit } print }
  ' "$1"
}

# trim_trailing_rule <file> → 末尾の空行と、その直前の `---` 区切りを取り除いて stdout
#   旧節を落とした結果、宙に浮いた区切り線が残るのを防ぐ（冪等性のために必要）。
trim_trailing_rule() {
  awk '
    { line[NR] = $0 }
    END {
      n = NR
      while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--
      if (n > 0 && line[n] ~ /^-{3,}[[:space:]]*$/) {
        n--
        while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--
      }
      for (i = 1; i <= n; i++) print line[i]
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# 同期
# ---------------------------------------------------------------------------
UPDATED=0
UNCHANGED=0
SKIPPED=0
REMOVED_STALE=0
SKIP_LIST=""
UPDATE_LIST=""
STALE_LIST=""
FAILED=0

TMP_WORK=$(mktemp -d) || {
  echo "ERROR: 一時ディレクトリを作成できませんでした。何も変更していません。" >&2
  exit 1
}
trap 'rm -rf "$TMP_WORK"' EXIT

for name in "${SPEC_DEFAULT_FILES[@]}"; do
  src="$SRC_SPEC/$name"
  dst="$DST_SPEC/$name"
  rel=".spec/$name"

  if [ ! -f "$dst" ]; then
    SKIPPED=$((SKIPPED + 1))
    SKIP_LIST="${SKIP_LIST}  - ${rel} — ファイルがありません"$'\n'
    continue
  fi

  if ! dst_bounds=$(spec_bounds "$dst"); then
    SKIPPED=$((SKIPPED + 1))
    SKIP_LIST="${SKIP_LIST}  - ${rel} — 既定節のマーカーが見つかりません（'# 既定の' / '# プロジェクト固有'）"$'\n'
    continue
  fi
  dst_start=${dst_bounds%% *}
  dst_end=${dst_bounds##* }

  new="$TMP_WORK/$name"
  tail_raw="$TMP_WORK/$name.tail"
  : >"$new"

  # 1) 既定節より前（見出し前の説明・書き方など）はそのまま残す
  if [ "$dst_start" -gt 1 ]; then
    head -n "$((dst_start - 1))" "$dst" >>"$new"
  fi

  # 2) 既定節をテンプレート版に差し替える
  if ! spec_extract_default "$src" >>"$new"; then
    echo "ERROR: テンプレート側の既定節を取得できませんでした: $src" >&2
    FAILED=1
    continue
  fi

  # 3) 固有節（'# プロジェクト固有' 行以降）はそのまま。ただし R2 の旧節だけ除去する
  tail -n +"$dst_end" "$dst" >"$tail_raw"
  stale=0
  # 除去条件は「新しい既定節に同じ節が含まれる」こと（Step 4-2 検証指摘の修正）。
  # テンプレート全体 ($src) を grep すると、旧世代テンプレートでは固有節側の節にヒットして
  # しまい、既定節に代替が入らないままプロジェクト側の節だけが消える（silent-wrong）
  if spec_extract_default "$src" | grep -q "$SPEC_AUTOREVIEWER_RE" \
     && grep -q "$SPEC_AUTOREVIEWER_RE" "$tail_raw"; then
    # 退避してから除去する（下流が旧節を独自加筆していた場合に備える。R3 と同じ思想）
    if ! $DRY_RUN; then
      bak_file="$DST_SPEC/removed-autoreviewer-$(basename "$dst" .md)-$(date +%Y%m%d-%H%M%S).bak"
      extract_old_autoreviewer "$tail_raw" >"$bak_file" 2>/dev/null || cp "$tail_raw" "$bak_file"
    fi
    strip_old_autoreviewer "$tail_raw" >"$tail_raw.stripped"
    trim_trailing_rule "$tail_raw.stripped" >"$tail_raw"
    stale=1
  fi
  cat "$tail_raw" >>"$new"

  # 4) 差分がなければ書き込まない（冪等）
  if cmp -s "$new" "$dst"; then
    UNCHANGED=$((UNCHANGED + 1))
    continue
  fi

  if [ "$stale" -eq 1 ]; then
    REMOVED_STALE=$((REMOVED_STALE + 1))
    STALE_LIST="${STALE_LIST}  - ${rel} — 固有節の後ろにあった旧「auto-reviewer への指示」節を除去しました"$'\n'
  fi

  if $DRY_RUN; then
    UPDATED=$((UPDATED + 1))
    UPDATE_LIST="${UPDATE_LIST}  - ${rel}（dry-run: 更新されます）"$'\n'
    continue
  fi

  # アトミック書き込み（D1-a と同じ原則。途中失敗で dst を破損させない）
  if ! { cp "$new" "$dst.tmp.$$" && mv "$dst.tmp.$$" "$dst"; }; then
    rm -f "$dst.tmp.$$"
    echo "ERROR: 書き込みに失敗しました（元ファイルは無変更）: $dst" >&2
    FAILED=1
    continue
  fi
  UPDATED=$((UPDATED + 1))
  UPDATE_LIST="${UPDATE_LIST}  - ${rel}"$'\n'
done

# ---------------------------------------------------------------------------
# サマリ
# ---------------------------------------------------------------------------
echo
echo "=== .spec 既定節の同期結果 ==="
echo "更新 $UPDATED / 変更なし $UNCHANGED / スキップ $SKIPPED"

if [ "$UPDATED" -gt 0 ]; then
  printf '%s' "$UPDATE_LIST"
fi

if [ "$REMOVED_STALE" -gt 0 ]; then
  echo
  echo "旧「## auto-reviewer への指示」節を $REMOVED_STALE 件除去しました（R2: 新旧の重複防止）:"
  printf '%s' "$STALE_LIST"
fi

if [ "$SKIPPED" -gt 0 ]; then
  echo
  echo "⚠️ 既定節のマーカーが無いためスキップしたファイルが $SKIPPED 件あります:" >&2
  printf '%s' "$SKIP_LIST" >&2
  echo "→ 手動でマーカー（'# 既定の...' / '# プロジェクト固有...'）を復旧してから再実行してください。" >&2
  echo "  スキップしたファイルはテンプレートの更新が届いていません。" >&2
fi

$DRY_RUN && echo "=== dry-run 完了（変更なし） ==="

if [ "$FAILED" -ne 0 ] || [ "$SKIPPED" -gt 0 ]; then
  exit 1
fi
exit 0
