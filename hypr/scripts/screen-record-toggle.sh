#!/usr/bin/env sh
set -eu

out_dir="${HOME}/Videos/Recordings"
mkdir -p "$out_dir"

if pgrep -x wf-recorder >/dev/null 2>&1; then
  pkill -INT -x wf-recorder || true
  if command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --custom-icon media-record --custom-message "Recording stopped" || true
  fi
  exit 0
fi

ts="$(date +%Y-%m-%d_%H-%M-%S)"
out_file="${out_dir}/screen-${ts}.mp4"
wf-recorder -f "$out_file" >/dev/null 2>&1 &

if command -v swayosd-client >/dev/null 2>&1; then
  swayosd-client --custom-icon media-record --custom-message "Recording started" || true
fi
