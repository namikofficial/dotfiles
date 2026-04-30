#!/usr/bin/env bash
set -euo pipefail

mode="${1:-count}"

case "$mode" in
  count) wayle notify list 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ' || echo 0 ;;
  dnd)
    state="$(wayle notify status 2>/dev/null | awk -F': ' '/Do Not Disturb/ {print $2}' | tr '[:upper:]' '[:lower:]' || echo false)"
    case "$state" in true|1|on|enabled) echo ON ;; *) echo OFF ;; esac
    ;;
  mode) echo "wayle" ;;
  recent) echo "Wayle owns notification history" ;;
  *) echo "n/a" ;;
esac
