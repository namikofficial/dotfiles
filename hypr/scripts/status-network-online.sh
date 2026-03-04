#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  echo false
  exit 0
fi

state="$(nmcli -t -f STATE g 2>/dev/null || echo unknown)"
case "$state" in
  connected|full|limited|portal) echo true ;;
  *) echo false ;;
esac
