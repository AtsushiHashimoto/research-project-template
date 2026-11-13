#!/usr/bin/env bash
# devcontainer の中の Claude Code（/voice）に、手元の PC のマイクの音を届ける受信側を起動する。
#
#   手元の PC（送信側）: マイクを録って s16le / 16 kHz / mono を localhost の TCP へ送る
#       ↓ VS Code の port forward
#   コンテナ（受信側）: recv.py が受けて、pacat で null sink「claude_mic」へ流す
#       ↓ claude_mic.monitor が既定の録音デバイス
#   Claude Code: ALSA の default（→ pulse）か arecord・rec で録る
#
# 導入は .devcontainer/install-voice.sh。何度実行してもよい（動いていれば何もしない）。
set -euo pipefail

CONF=/etc/pulse/client.conf.d/claude-voice.conf
if [ ! -f "$CONF" ]; then
  echo "[voice] voice dictation は入っていない（選んでいなければ正常）。使うなら .devcontainer/options.env に CLAUDE_VOICE=true を書いて Rebuild Container、または sudo bash .devcontainer/install-voice.sh" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINK="$(python3 "$HERE/recv.py" --print-sink)"
RUN="$(sed -n 's|^default-server = unix:\(.*\)/native$|\1|p' "$CONF")"
[ -n "$RUN" ] || { echo "[voice] ERROR: $CONF から socket の場所を読めない" >&2; exit 1; }

if [ -L "$RUN" ] || { [ -e "$RUN" ] && [ ! -O "$RUN" ]; }; then
  echo "[voice] ERROR: $RUN が自分のものではない（sudo で起動した跡なら sudo rm -rf $RUN）" >&2
  exit 1
fi
mkdir -p "$RUN"
chmod 700 "$RUN"
# 状態の置き場所を RUN に寄せる（~/.config が書けない環境でも起動できるように）
export PULSE_STATE_PATH="$RUN/state" PULSE_RUNTIME_PATH="$RUN/runtime"

if ! pactl info >/dev/null 2>&1; then
  # 認証は socket を置くディレクトリの権限（700）で行う。cookie は使わない
  pulseaudio --daemonize=yes --exit-idle-time=-1 --log-target="file:$RUN/pulseaudio.log" -n \
    -L "module-native-protocol-unix socket=$RUN/native auth-cookie-enabled=0 auth-anonymous=1" \
    -L "module-always-sink" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pactl info >/dev/null 2>&1 && break
    sleep 0.3
  done
  if ! pactl info >/dev/null 2>&1; then
    echo "[voice] ERROR: PulseAudio を起動できない（log: $RUN/pulseaudio.log）" >&2
    exit 1
  fi
fi
sinks="$(pactl list short sinks)"
case "$sinks" in
  *"$SINK"*) ;;
  *) pactl load-module module-null-sink "sink_name=$SINK" "sink_properties=device.description=$SINK" \
       rate=16000 channels=1 format=s16le >/dev/null ;;
esac
pactl set-default-sink "$SINK"
pactl set-default-source "$SINK.monitor"

# recv.py が生きているかは PID で見る（番号に繋いで確かめると、その接続が音の接続として記録される）
pid="$(cat "$RUN/recv.pid" 2>/dev/null || true)"
alive() { [ -n "$pid" ] && grep -qa "voice/recv.py" "/proc/$pid/cmdline" 2>/dev/null; }
if ! alive; then
  setsid nohup python3 -u "$HERE/recv.py" > "$RUN/recv.log" 2>&1 < /dev/null &
  pid=$!
  echo "$pid" > "$RUN/recv.pid"
  sleep 1
  if ! alive; then
    echo "[voice] ERROR: recv.py を起動できない（番号が使われている等）:" >&2
    tail -n 3 "$RUN/recv.log" >&2
    exit 1
  fi
fi
echo "[voice] 受信待ち: 127.0.0.1:$(python3 "$HERE/recv.py" --print-port)（log: $RUN/recv.log）"
