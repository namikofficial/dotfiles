#!/usr/bin/env sh
set -eu

if ! command -v tlp-stat >/dev/null 2>&1; then
  exit 0
fi

cmd="tlp-stat -s"
if command -v kitty >/dev/null 2>&1; then
  kitty sh -lc "$cmd; printf '\n'; read -r -p 'Press enter to close'" >/dev/null 2>&1 &
  exit 0
fi
if command -v foot >/dev/null 2>&1; then
  foot -e sh -lc "$cmd" >/dev/null 2>&1 &
  exit 0
fi
if command -v alacritty >/dev/null 2>&1; then
  alacritty -e sh -lc "$cmd" >/dev/null 2>&1 &
  exit 0
fi
if command -v wezterm >/dev/null 2>&1; then
  wezterm start -- sh -lc "$cmd" >/dev/null 2>&1 &
  exit 0
fi
