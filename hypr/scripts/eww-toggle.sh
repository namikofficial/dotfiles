#!/usr/bin/env sh
set -eu

# Super+Y overlay is intentionally disabled for stability.
# This script is kept as a safe cleanup helper.

cfg="$HOME/.config/eww"

if ! command -v eww >/dev/null 2>&1; then
  exit 0
fi

eww --config "$cfg" close quickpanel-main >/dev/null 2>&1 || true
eww --config "$cfg" close quickpanel >/dev/null 2>&1 || true
