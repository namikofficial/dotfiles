#!/usr/bin/env sh
set -eu

if ! command -v hyprctl >/dev/null 2>&1; then
  echo "󰽀 n/a"
  exit 0
fi

layout="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.tiledLayout // "dwindle"' 2>/dev/null || echo dwindle)"

case "$layout" in
  master) echo " master" ;;
  dwindle) echo " dwindle" ;;
  *) echo "󰽀 $layout" ;;
esac
