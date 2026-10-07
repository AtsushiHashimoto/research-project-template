#!/usr/bin/env bash
# source-only: quality-check.sh の検査結果を報告して終了。呼出元が状態を設定する。
# shellcheck disable=SC2154,SC2153  # 状態は呼出元の quality-check.sh が設定する。
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
