#!/usr/bin/env sh
set -eu

if command -v eww >/dev/null 2>&1 && \
  eww --config "$HOME/.config/eww" active-windows 2>/dev/null | grep -Eq '^(desktop-left:|desktop-right:)'; then
  echo true
else
  echo false
fi
