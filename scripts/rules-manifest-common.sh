#!/usr/bin/env bash
# ============================================================
# .claude/rules/template/MANIFEST.sha256 の共通処理
# [Template] research-project-template 由来
# ============================================================
#
# **source 専用。単独では実行しない。** 以下から読み込まれる:
#   - scripts/generate-rules-manifest.sh  … MANIFEST の生成（テンプレート開発者用）
#   - scripts/template-sync-rules.sh      … MANIFEST の照合（下流プロジェクトの sync）
#
# MANIFEST の形式は `shasum -a 256` / `sha256sum` 互換:
#   <sha256>␣␣<ファイル名>
# ディレクトリ内で `shasum -a 256 -c MANIFEST.sha256` により検証できる。
# MANIFEST 自身は一覧に含めない。

RULES_MANIFEST_NAME="MANIFEST.sha256"

# sha256_of <file> → ハッシュ文字列のみを stdout に出力
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "ERROR: sha256sum も shasum も見つかりません（sha256 が計算できない）" >&2
    return 1
  fi
}

# manifest_write <dir> → <dir>/MANIFEST.sha256 を生成
#   対象は <dir> 直下の *.md のみ。ファイル名順（LC_ALL=C）で安定出力するため冪等。
manifest_write() {
  local dir="$1"
  local out="$dir/$RULES_MANIFEST_NAME"
  local tmp file name hash count=0

  [ -d "$dir" ] || { echo "ERROR: ディレクトリがありません: $dir" >&2; return 1; }

  tmp=$(mktemp) || return 1
  while IFS= read -r file; do
    name=$(basename "$file")
    hash=$(sha256_of "$file") || { rm -f "$tmp"; return 1; }
    printf '%s  %s\n' "$hash" "$name" >>"$tmp"
    count=$((count + 1))
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)

  if [ "$count" -eq 0 ]; then
    rm -f "$tmp"
    echo "ERROR: 対象の .md がありません: $dir" >&2
    return 1
  fi

  if ! chmod 0644 "$tmp" || ! mv "$tmp" "$out"; then
    rm -f "$tmp"
    echo "ERROR: MANIFEST の書き出しに失敗しました: $out" >&2
    return 1
  fi
  echo "$count"
}

# manifest_expected <manifest> <name> → 期待ハッシュを出力。未登録なら非0
manifest_expected() {
  local manifest="$1" name="$2"
  [ -f "$manifest" ] || return 1
  awk -v n="$name" '$2 == n { print $1; found = 1 } END { exit(found ? 0 : 1) }' "$manifest"
}

# manifest_check <dir> → <dir> の実ファイルと MANIFEST.sha256 の整合を検査
#   不整合（MANIFEST 不在 / ハッシュ不一致 / 未登録の追加 / 登録済みの欠落）があれば
#   内容を stderr に出して非0で返る。テンプレート開発者の CI / quality-check 用。
manifest_check() {
  local dir="$1"
  local manifest="$dir/$RULES_MANIFEST_NAME"
  local name expected actual bad=0

  [ -d "$dir" ] || { echo "ERROR: ディレクトリがありません: $dir" >&2; return 1; }

  if [ ! -f "$manifest" ]; then
    echo "ERROR: $RULES_MANIFEST_NAME がありません: $manifest" >&2
    echo "  bash scripts/generate-rules-manifest.sh を実行してコミットに含めてください。" >&2
    return 1
  fi

  # 実ファイル → MANIFEST
  while IFS= read -r file; do
    name=$(basename "$file")
    if ! expected=$(manifest_expected "$manifest" "$name"); then
      echo "MANIFEST 不整合: $name が $RULES_MANIFEST_NAME に登録されていません" >&2
      bad=1
      continue
    fi
    actual=$(sha256_of "$file") || { bad=1; continue; }
    if [ "$actual" != "$expected" ]; then
      echo "MANIFEST 不整合: $name のハッシュが一致しません（ファイルを変更したら再生成が必要）" >&2
      bad=1
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)

  # MANIFEST → 実ファイル
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ ! -f "$dir/$name" ]; then
      echo "MANIFEST 不整合: $name が $RULES_MANIFEST_NAME にあるが実ファイルがありません" >&2
      bad=1
    fi
  done < <(awk '{ print $2 }' "$manifest")

  if [ "$bad" -ne 0 ]; then
    echo "  → bash scripts/generate-rules-manifest.sh を実行して再生成してください。" >&2
    return 1
  fi
  return 0
}
