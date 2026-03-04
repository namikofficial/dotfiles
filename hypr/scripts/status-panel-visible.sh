#!/usr/bin/env sh
set -eu

if pgrep -x waybar >/dev/null 2>&1 || pgrep -x hyprpanel >/dev/null 2>&1 || pgrep -x ags >/dev/null 2>&1; then
  echo true
else
  echo false
fi
