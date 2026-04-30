#!/usr/bin/env bash
set -euo pipefail

mode="${1:-count}"

case "$mode" in
  count) swaync-client -sw -c 2>/dev/null || echo 0 ;;
  dnd)
    state="$(swaync-client -sw -D 2>/dev/null || echo false)"
    case "$state" in true|1|on|enabled) echo ON ;; *) echo OFF ;; esac
    ;;
  mode) echo "swaync" ;;
  recent) echo "SwayNC owns notification history" ;;
  *) echo "n/a" ;;
esac
