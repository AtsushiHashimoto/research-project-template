#!/usr/bin/env bash
# ============================================================
# Claude Code native build installer (called from post-create.sh)
# [Template] research-project-template 由来
# ============================================================
# ~/.local/bin/claude に native build を入れ、版が下限以上であることを確かめる（#151）。
# - npm 版（root 所有の global prefix）は auto-update が権限エラーで失敗するため使わない
# - ~/.local は永続化されないので rebuild ごとに入れ直す
# - 実行可能かつ下限以上の版が既にあれば導入を省く（版チェックは常に行う）
# - sudo を付けない（インストーラが拒否する）
# 単体でも実行できる: bash .devcontainer/install-claude-native.sh
set -euo pipefail

# ★ 下限とチャネルはここだけに書く（単一情報源）
MIN_VERSION_DEFAULT=2.1.280
CHANNEL=latest
INSTALLER_URL=https://claude.ai/install.sh

BIN="$HOME/.local/bin/claude"
TAG="[post-create:claude]"

log() { echo "$TAG $*"; }

fail() {
  # $1: 段階（download / installer / version）、$2: 理由
  {
    echo "$TAG FAIL ($1: $2)"
    echo "$TAG 手動で再実行: bash .devcontainer/install-claude-native.sh"
    echo "$TAG post-create が止まった場合は: bash .devcontainer/post-create.sh <name> の後に bash .devcontainer/post-start.sh"
  } >&2
  exit 1
}

# 下限は試験用に CLAUDE_NATIVE_MIN_VERSION で上書きできる（上書き時は必ずログに出す）
MIN_VERSION="$MIN_VERSION_DEFAULT"
if [ -n "${CLAUDE_NATIVE_MIN_VERSION:-}" ]; then
  MIN_VERSION="$CLAUDE_NATIVE_MIN_VERSION"
  log "MIN_VERSION overridden by CLAUDE_NATIVE_MIN_VERSION=$MIN_VERSION (default $MIN_VERSION_DEFAULT)"
fi

# 版を取り出して stdout に出す。取り出せなければ理由を stdout に出して非ゼロで返す。
# 導入要否の判定と最後の版チェックで共用する（ロジックを 2 か所に書かない）
get_version() {
  local bin=$1 out ver
  if [ ! -x "$bin" ]; then
    echo "missing: $bin is not executable"
    return 1
  fi
  # timeout: 固まった launcher で post-create 全体が止まらないようにする
  if ! out=$(timeout 30 "$bin" --version 2>&1); then
    echo "'$bin --version' exited non-zero or timed out: ${out:-<empty>}"
    return 1
  fi
  # 先頭行だけでなく全行から探す（警告などが先に出ても版を取り出せるように）。
  # grep の不一致（非ゼロ）で set -e / pipefail に殺されないよう || true で受ける
  ver=$(printf '%s\n' "$out" | grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)
  if [ -n "$ver" ]; then
    echo "$ver"
    return 0
  fi
  echo "cannot parse version from: ${out:-<empty>}"
  return 1
}

# $1 >= MIN_VERSION なら真
version_ok() {
  [ "$(printf '%s\n' "$MIN_VERSION" "$1" | sort -V | head -n1)" = "$MIN_VERSION" ]
}

# --- 導入要否 ---
need_install=0
if v=$(get_version "$BIN"); then
  if version_ok "$v"; then
    log "skip (found $v)"
  else
    log "install (reason: found $v < $MIN_VERSION)"
    need_install=1
  fi
else
  log "install (reason: $v)"
  need_install=1
fi

# --- 導入 ---
if [ "$need_install" = 1 ]; then
  # 作業ディレクトリを $HOME に固定する（/ や大きな /workspace からの実行を避ける）。
  # cd はサブシェル内だけで行い、呼び出し元に影響させない
  (
    cd "$HOME" || fail installer "cannot cd to $HOME"
    tmp=$(mktemp) || fail installer "mktemp failed"
    trap 'rm -f "$tmp"' EXIT
    curl -fsSL --retry 3 --retry-connrefused --connect-timeout 20 -o "$tmp" "$INSTALLER_URL" \
      || fail download "curl $INSTALLER_URL failed"
    # 既存の launcher（壊れたリンク・下限未満・版を返さないもの）を退避してから導入する。
    # インストーラは自分が作ったと判断できない launcher を上書きせず（壊れたリンクでは失敗、
    # 通常ファイルでは成功と表示して置き換えない）、再導入で直らなくなるため（実測）。
    # 退避は取得に成功した後で行い（取得失敗で既存を触らない）、インストーラが失敗したら戻す
    bak=""
    if [ -e "$BIN" ] || [ -L "$BIN" ]; then
      bak="$BIN.pre-install.$$"
      mv -f -- "$BIN" "$bak" || fail installer "cannot move aside $BIN"
      log "moved stale launcher aside: $BIN -> $bak"
    fi
    if ! bash "$tmp" "$CHANNEL"; then
      # 戻す処理は fail の前に明示的に行う（EXIT trap に任せない）。
      # if の条件部は set -e の対象外なので、mv の失敗で止まらずログを出してから fail に進む
      # （`A && B || C` は B の失敗でも C が走るため if で書く。SC2015）
      if [ -n "$bak" ] && [ ! -e "$BIN" ] && [ ! -L "$BIN" ]; then
        if mv -f -- "$bak" "$BIN"; then
          log "restored $BIN"
        else
          log "restore failed; old launcher kept at $bak"
        fi
      elif [ -n "$bak" ]; then
        log "installer left a new $BIN; old launcher kept at $bak"
      fi
      fail installer "bash install.sh $CHANNEL failed"
    fi
    # ★ `[ -n "$bak" ] && rm` と書かない: bak が空のとき偽がサブシェルの終了コードになり、
    #   set -e の親が成功した導入を失敗として止めてしまう
    # ★ インストーラが成功を返しても launcher を作らないことがある。新しい launcher が
    #   実行可能なときだけ退避を消し、作られていなければ戻して fail する（戻さずに消すと
    #   既存の launcher を失う。レビューで再現）
    if [ -n "$bak" ]; then
      if [ -x "$BIN" ]; then
        rm -f -- "$bak"
      elif [ ! -e "$BIN" ] && [ ! -L "$BIN" ]; then
        if mv -f -- "$bak" "$BIN"; then
          log "restored $BIN (installer created no launcher)"
        else
          log "restore failed; old launcher kept at $bak"
        fi
        fail installer "install.sh reported success but did not create $BIN"
      else
        log "installer left a non-executable $BIN; old launcher kept at $bak"
      fi
    fi
  )
fi

# --- 版チェック（導入の有無にかかわらず必ず行う） ---
if ! v=$(get_version "$BIN"); then
  fail version "$v"
fi
if ! version_ok "$v"; then
  fail version "$v < $MIN_VERSION"
fi
log "ok ($v >= $MIN_VERSION)"

if [ "$need_install" = 1 ]; then
  log "readlink -f $BIN: $(readlink -f "$BIN")"
  # 診断出力のみ（npm 版などが先に解決されていないかを見る）。合否には使わない
  if resolved=$(type -a claude 2>&1); then
    log "type -a claude:"
    printf '%s\n' "$resolved" | sed "s/^/$TAG   /"
  else
    log "type -a claude: not found on PATH ($PATH)"
  fi
fi
