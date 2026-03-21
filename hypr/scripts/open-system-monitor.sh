#!/usr/bin/env sh
set -eu

cmd=""
if command -v btop >/dev/null 2>&1; then
  cmd="btop"
elif command -v htop >/dev/null 2>&1; then
  cmd="htop"
fi

[ -n "$cmd" ] || exit 0

if command -v kitty >/dev/null 2>&1; then
  kitty sh -lc "$cmd; read -r -p 'Press enter to close'" >/dev/null 2>&1 &
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
