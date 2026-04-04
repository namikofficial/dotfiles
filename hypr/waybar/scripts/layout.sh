#!/usr/bin/env sh
set -eu

state_file="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/layout-mode"
layout=""

if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  layout="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.tiledLayout // empty' 2>/dev/null || true)"
fi

if [ -z "$layout" ] && [ -f "$state_file" ]; then
  layout="$(cat "$state_file" 2>/dev/null || true)"
fi

case "$layout" in
  master) echo " master" ;;
  dwindle) echo " dwindle" ;;
  allfloat) echo "󰖲 float" ;;
  allpseudo) echo "󰊠 pseudo" ;;
  "") echo "󰽀 n/a" ;;
  *) echo "󰽀 $layout" ;;
esac
