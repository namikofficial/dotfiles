#!/usr/bin/env sh
set -eu

mode="${1:-area}"
out_dir="$HOME/Pictures/Screenshots"
mkdir -p "$out_dir"
file="$out_dir/$(date +%Y-%m-%d_%H-%M-%S).png"

if [ "$mode" = "full" ]; then
  grim "$file"
else
  grim -g "$(slurp)" "$file"
fi

if command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$file"
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send "Screenshot saved" "$file"
fi
