#!/usr/bin/env sh
set -eu

ROFI_THEME="$HOME/.config/rofi/launcher.rasi"

exec rofi \
  -show drun \
  -modi 'drun,window,run' \
  -matching fuzzy \
  -sort \
  -show-icons \
  -i \
  -p 'Apps' \
  -theme "$ROFI_THEME"
