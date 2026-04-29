#!/usr/bin/env sh
set -eu

url="${SYNCTHING_UI_URL:-http://127.0.0.1:8384/}"

if ! command -v xdg-open >/dev/null 2>&1; then
  command -v notify-send >/dev/null 2>&1 && notify-send -a Syncthing "Cannot open Syncthing UI" "xdg-open is missing" || true
  exit 1
fi

xdg-open "$url" >/dev/null 2>&1 &
