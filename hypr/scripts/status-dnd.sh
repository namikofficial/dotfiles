#!/usr/bin/env sh
set -eu

state="$(wayle notify status 2>/dev/null | awk -F': ' '/Do Not Disturb/ {print $2}' | tr '[:upper:]' '[:lower:]' || echo false)"
case "$state" in
  true|1|on|enabled) echo true ;;
  *) echo false ;;
esac
