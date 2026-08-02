#!/usr/bin/env bash
# ============================================================
# .claude/rules/template/ の同期（/template-sync の rules 処理の実体）
# [Template] research-project-template 由来
# ============================================================
#
# `.claude/rules/` の構成:
#   .claude/rules/template/   テンプレート由来。本スクリプトが**丸ごと置き換える**
#   .claude/rules/*.md        プロジェクトローカル。本スクリプトは**一切触らない**
#
# 動作:
#   1. 前回の失敗で残った `.template.new/` を除去する
#   2. テンプレートの `rules/template/` を `.template.new/` に展開する（失敗したら無変更で異常終了）
#   3. 既存 `template/` を MANIFEST.sha256 と照合し、**ローカル改変ファイルを退避**する
#      （退避先 `template.bak-<YYYYMMDD-HHMMSS>/template/`。これが還流候補になる）
#   4. #91 フラット世代の `rules/` 直下にある**テンプレート既知名のファイル**を処理する
#      （新版と内容一致なら削除、証明できなければ退避、未知の名前はローカルルールとして保持）
#   5. `rm -rf template/` → `mv .template.new template/` でアトミックに入れ替える
#
# 安全側の既定（仕様 #100 D1-a/D1-b、残課題 R1/R3）:
#   - ハッシュで「テンプレートと同一」と証明できないファイルは**削除せず退避**する
#   - MANIFEST が無い場合（初回・旧構造）は全ファイルを改変扱いで退避する
#   - 取得・展開に失敗した場合は**何も変更せず非0 exit**（無言 exit 0 は禁止）
#
# Usage:
#   bash scripts/template-sync-rules.sh --source <template-checkout-dir> [options]
#   bash scripts/template-sync-rules.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=rules-manifest-common.sh
. "$SCRIPT_DIR/rules-manifest-common.sh"

usage() {
  cat <<'EOF'
.claude/rules/template/ をテンプレートの最新版に同期する。
rules/ 直下のローカルルールには触らない。ローカル改変は退避してから置き換える。

Usage:
  bash scripts/template-sync-rules.sh --source <template-checkout-dir> [options]

Options:
  --source <dir>        必須。テンプレートを clone / 展開したディレクトリ。
                        <dir>/.claude/rules/template/ を取り込む
  --project-root <dir>  取り込み先。既定はカレントの git リポジトリルート
  --dry-run             何も変更せず、実行される処理だけを表示する
  -h, --help            この使い方を表示する

Exit codes:
  0  同期成功（変更なしを含む）
  1  失敗（取得・展開・入れ替えのいずれかが失敗。作業ツリーは原則無変更）
  2  引数エラー

Example:
  TMP_DIR=$(mktemp -d)
  # テンプレートの URL は scripts/template-source.sh が単一情報源（ハードコードしない）
  git clone --depth 1 "$(bash scripts/template-source.sh)" "$TMP_DIR/template" || exit 1
  bash scripts/template-sync-rules.sh --source "$TMP_DIR/template"
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

# ---------------------------------------------------------------------------
# 事前チェック（ここで失敗する場合は作業ツリーを一切変更しない）
# ---------------------------------------------------------------------------
SRC_RULES="$SOURCE_DIR/.claude/rules/template"
RULES_DIR="$PROJECT_ROOT/.claude/rules"
DEST="$RULES_DIR/template"

# 移行モードの判定: template/ が無い状態からの sync は旧構造（#91 フラット世代 or 初回）。
# 孤児ファイル処理（Step 4）は移行モードでのみ実行する。
# template/ が既に存在する場合、rules/ 直下の同名ファイルは意図的なローカル上書きと
# みなして触らない（CLAUDE.md「直下は一切触らない」の契約を守る。検証指摘 F-A 対応）
if [ -d "$DEST" ]; then MIGRATION=0; else MIGRATION=1; fi
STAGE="$RULES_DIR/.template.new"

if [ ! -d "$PROJECT_ROOT/.claude" ]; then
  echo "ERROR: 取り込み先がプロジェクトルートではありません（.claude/ が無い）: $PROJECT_ROOT" >&2
  echo "  --project-root で明示してください。" >&2
  exit 1
fi

if [ ! -d "$SRC_RULES" ]; then
  echo "ERROR: テンプレートの取得に失敗しています（rules/template/ が見つかりません）" >&2
  echo "  探した場所: $SRC_RULES" >&2
  echo "  clone が失敗していないか、--source の指定が正しいかを確認してください。" >&2
  echo "  何も変更していません。" >&2
  exit 1
fi

SRC_COUNT=$(find "$SRC_RULES" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
if [ "$SRC_COUNT" -eq 0 ]; then
  echo "ERROR: テンプレートの rules/template/ に .md がありません: $SRC_RULES" >&2
  echo "  取得が不完全な可能性があります。何も変更していません。" >&2
  exit 1
fi

DEST_MANIFEST="$DEST/$RULES_MANIFEST_NAME"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BAK_DIR="$RULES_DIR/template.bak-$TIMESTAMP"

echo "=== rules 同期 ==="
echo "  from: $SRC_RULES"
echo "  to  : $DEST"
$DRY_RUN && echo "  mode: dry-run（変更しません）"

# ---------------------------------------------------------------------------
# 内部関数
# ---------------------------------------------------------------------------
BAK_USED=false

ensure_bak_dir() {
  BAK_USED=true
  $DRY_RUN && return 0
  mkdir -p "$1"
}

# stash_file <src-file> <bak-subdir> <relpath> <copy|move>
stash_file() {
  local src="$1" subdir="$2" rel="$3" mode="$4"
  local dst="$BAK_DIR/$subdir/$rel"
  ensure_bak_dir "$(dirname "$dst")"
  $DRY_RUN && return 0
  if [ "$mode" = "move" ]; then
    mv "$src" "$dst"
  else
    cp -p "$src" "$dst"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: 前回の残骸を除去（R1: 残っていると cp -r が入れ子にコピーしてしまう）
# ---------------------------------------------------------------------------
if [ -e "$STAGE" ]; then
  echo "--- 前回の残骸を除去: $STAGE"
  if ! $DRY_RUN && ! rm -rf "$STAGE"; then
    echo "ERROR: 残骸の除去に失敗しました: $STAGE" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: 一時領域に展開（ここまでは template/ を触らない）
# ---------------------------------------------------------------------------
if ! $DRY_RUN; then
  if ! mkdir -p "$RULES_DIR" || ! cp -R "$SRC_RULES" "$STAGE"; then
    echo "ERROR: テンプレートの展開に失敗しました: $SRC_RULES → $STAGE" >&2
    echo "  何も変更していません（既存の template/ はそのままです）。" >&2
    rm -rf "$STAGE"
    exit 1
  fi
  # テンプレート側に MANIFEST が無い旧版でも、次回 sync のために生成しておく
  if [ ! -f "$STAGE/$RULES_MANIFEST_NAME" ]; then
    echo "--- テンプレート側に $RULES_MANIFEST_NAME が無いため生成します（旧世代テンプレート）"
    if ! manifest_write "$STAGE" >/dev/null; then
      echo "ERROR: MANIFEST の生成に失敗しました" >&2
      rm -rf "$STAGE"
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: 既存 template/ のローカル改変を検出して退避
# ---------------------------------------------------------------------------
STASHED_COUNT=0
STASHED_LIST=""

if [ -d "$DEST" ]; then
  if [ ! -f "$DEST_MANIFEST" ]; then
    echo "--- $RULES_MANIFEST_NAME が無いため、既存 template/ を全件退避します（初回 / 旧構造）"
  fi
  while IFS= read -r rel; do
    rel="${rel#./}"
    [ "$rel" = "$RULES_MANIFEST_NAME" ] && continue
    reason=""
    if [ ! -f "$DEST_MANIFEST" ]; then
      reason="MANIFEST 不在のため改変の有無を判定できない"
    else
      expected=$(manifest_expected "$DEST_MANIFEST" "$rel")
      if [ -z "$expected" ]; then
        reason="MANIFEST に未登録（ローカル追加または旧版）"
      elif [ "$(sha256_of "$DEST/$rel")" != "$expected" ]; then
        reason="ローカル改変あり"
      fi
    fi
    if [ -n "$reason" ]; then
      stash_file "$DEST/$rel" "template" "$rel" copy || {
        echo "ERROR: 退避に失敗しました: $rel" >&2
        rm -rf "$STAGE"
        exit 1
      }
      STASHED_COUNT=$((STASHED_COUNT + 1))
      STASHED_LIST="${STASHED_LIST}  - template/${rel} — ${reason}"$'\n'
    fi
  done < <(cd "$DEST" && find . -type f | LC_ALL=C sort)
fi

# ---------------------------------------------------------------------------
# Step 4: #91 フラット世代の孤児ファイル（rules/ 直下）
#   テンプレート既知名 かつ 新版と内容一致 → 削除（template/ の同内容に置き換わる）
#   テンプレート既知名 だが 一致を証明できない → 退避（R3: 既定は削除ではなく退避）
#   未知の名前 → ローカルルールとして保持
# ---------------------------------------------------------------------------
ORPHAN_REMOVED=0
ORPHAN_STASHED=0
ORPHAN_KEPT=0
ORPHAN_LIST=""

if [ "$MIGRATION" -eq 1 ]; then
for path in "$RULES_DIR"/*.md; do
  [ -e "$path" ] || continue   # glob 不一致（rules/ 直下にローカルルールが無い）
  name=$(basename "$path")
  if [ ! -f "$SRC_RULES/$name" ]; then
    ORPHAN_KEPT=$((ORPHAN_KEPT + 1))
    ORPHAN_LIST="${ORPHAN_LIST}  - ${name} — 保持（ローカルルール）"$'\n'
    continue
  fi
  # ハッシュを先に取得し、空（=計算失敗）なら一致とみなさない（検証指摘 F-B 対応。
  # 空同士の文字列比較が「一致」となり削除される経路を塞ぐ。R3: 証明できなければ退避）
  h_local=$(sha256_of "$path") || h_local=""
  h_src=$(sha256_of "$SRC_RULES/$name") || h_src=""
  if [ -n "$h_local" ] && [ "$h_local" = "$h_src" ]; then
    # 新版と同一内容であることをハッシュで証明できた場合のみ削除する
    $DRY_RUN || rm -f "$path"
    ORPHAN_REMOVED=$((ORPHAN_REMOVED + 1))
    ORPHAN_LIST="${ORPHAN_LIST}  - ${name} — 削除（template/ の新版と同一内容）"$'\n'
  else
    stash_file "$path" "flat" "$name" move || {
      echo "ERROR: 孤児ファイルの退避に失敗しました: $name" >&2
      rm -rf "$STAGE"
      exit 1
    }
    ORPHAN_STASHED=$((ORPHAN_STASHED + 1))
    ORPHAN_LIST="${ORPHAN_LIST}  - ${name} — 退避（テンプレート版と一致を証明できない）"$'\n'
  fi
done
fi

# ---------------------------------------------------------------------------
# Step 5: アトミックな入れ替え
# ---------------------------------------------------------------------------
if $DRY_RUN; then
  echo "--- [dry-run] rm -rf '$DEST' && mv '$STAGE' '$DEST'"
else
  if [ -d "$DEST" ] && ! rm -rf "$DEST"; then
    echo "ERROR: 既存 template/ の削除に失敗しました: $DEST" >&2
    echo "  展開済みの新版は $STAGE に残しています。" >&2
    exit 1
  fi
  if ! mv "$STAGE" "$DEST"; then
    echo "ERROR: 入れ替えに失敗しました。現在 template/ が不在の状態です。" >&2
    echo "  復旧してください: mv '$STAGE' '$DEST'" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# サマリ
# ---------------------------------------------------------------------------
echo
echo "=== rules 同期の結果 ==="
echo "同期: .claude/rules/template/（$SRC_COUNT ファイル）"

if [ "$STASHED_COUNT" -gt 0 ]; then
  echo
  echo "⚠️ ローカル改変を $STASHED_COUNT 件検出し、退避しました（還流候補）:"
  printf '%s' "$STASHED_LIST"
  echo "退避先: ${BAK_DIR#"$PROJECT_ROOT"/}/template/"
  echo "→ /template-contribute を実行して、テンプレートに還流するか判断してください。"
fi

if [ $((ORPHAN_REMOVED + ORPHAN_STASHED + ORPHAN_KEPT)) -gt 0 ]; then
  echo
  echo "旧構造（rules/ 直下）のファイル処理: 削除 $ORPHAN_REMOVED / 退避 $ORPHAN_STASHED / 保持 $ORPHAN_KEPT"
  printf '%s' "$ORPHAN_LIST"
  if [ "$ORPHAN_STASHED" -gt 0 ]; then
    echo "退避先: ${BAK_DIR#"$PROJECT_ROOT"/}/flat/"
  fi
fi

if [ "$STASHED_COUNT" -eq 0 ] && [ "$ORPHAN_STASHED" -eq 0 ]; then
  echo "退避: なし（ローカル改変は検出されませんでした）"
fi

$BAK_USED && $DRY_RUN && echo "（dry-run のため退避ディレクトリは作成していません）"
$DRY_RUN && echo "=== dry-run 完了（変更なし） ==="

exit 0
