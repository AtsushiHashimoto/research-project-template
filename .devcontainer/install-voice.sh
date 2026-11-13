#!/usr/bin/env bash
# ============================================================
# Claude Code の voice dictation（/voice）を devcontainer で使うための導入（root で実行）
# [Template] research-project-template 由来
# ============================================================
#   install-voice.sh                        導入する（作り直さずに入れるとき: sudo bash .devcontainer/install-voice.sh）
#   install-voice.sh --if-enabled <file>    <file>（.devcontainer/options.env）が有効にしているときだけ導入する。Dockerfile が呼ぶ
#   install-voice.sh --check <file>         判定だけ出す（enabled / disabled）。導入しない
# 起動は scripts/voice/start.sh（post-start.sh が呼ぶ）。使い方は optional-features.md。
set -euo pipefail

# <file> の CLAUDE_VOICE を読む。true なら 0、false・行が無い・ファイルが無いなら 1。
# 読めない値は 2（黙って「入れない」に倒すと、選んだのに入っていない理由に気づけない）。
# 行末の CR・前後の空白・引用符・export は許す（Windows の checkout や手書きで付く）
voice_enabled() {
  local file="$1" value
  [ -f "$file" ] || return 1
  value="$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}CLAUDE_VOICE=//p' "$file" | tail -n 1)"
  value="$(printf '%s' "$value" | sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'\''\(.*\)'\''$/\1/')"
  case "$value" in
    true) return 0 ;;
    false | "") return 1 ;;
    *)
      echo "[install-voice] ERROR: $file の CLAUDE_VOICE=$value を読めない（true か false を書く）" >&2
      return 2
      ;;
  esac
}

install_voice() {
  # コンテナにはマイクが無いので、手元の PC から届いた音を PulseAudio の null sink に流し、
  # その monitor を既定の録音デバイスとして見せる。
  #   pulseaudio / pulseaudio-utils … サーバーと pactl・pacat
  #   libasound2-plugins            … ALSA → PulseAudio（Claude Code は ALSA を直接開く）
  #   alsa-utils / sox / libsox-fmt-pulse … Claude Code が代わりに使う arecord・rec
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    pulseaudio pulseaudio-utils libasound2-plugins alsa-utils sox libsox-fmt-pulse
  apt-get clean && rm -rf /var/lib/apt/lists/*

  # ALSA の default を PulseAudio に向ける
  mkdir -p /etc/alsa/conf.d
  cat > /etc/alsa/conf.d/99-pulseaudio-default.conf <<'CONF'
pcm.!default { type pulse }
ctl.!default { type pulse }
CONF

  # どのプロセスも（環境変数なしで）同じ socket に繋がるようにする。
  # ★ socket の場所はここが単一情報源（scripts/voice/start.sh はこのファイルから読む）。
  #   このファイルが在ることが「導入済み」の印でもある（post-start.sh・start.sh が見る）
  mkdir -p /etc/pulse/client.conf.d
  cat > /etc/pulse/client.conf.d/claude-voice.conf <<'CONF'
default-server = unix:/tmp/claude-voice/native
autospawn = no
CONF
}

case "${1:-}" in
  "") install_voice ;;
  --check)
    if voice_enabled "${2:?file}"; then echo enabled; else rc=$?; [ "$rc" = 1 ] || exit "$rc"; echo disabled; fi
    ;;
  --if-enabled)
    if voice_enabled "${2:?file}"; then
      install_voice
    else
      rc=$?
      [ "$rc" = 1 ] || exit "$rc"
      echo "[install-voice] voice dictation は入れない（$2 に CLAUDE_VOICE=true が無い）"
    fi
    ;;
  *) echo "usage: install-voice.sh [--if-enabled <file> | --check <file>]" >&2; exit 2 ;;
esac
