#!/usr/bin/env sh
set -eu

state="$(swaync-client -D 2>/dev/null || echo false)"
case "$state" in
  true|1|on|enabled) echo true ;;
  *) echo false ;;
esac
