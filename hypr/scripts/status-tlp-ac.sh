#!/usr/bin/env sh
set -eu

if ! command -v tlp-stat >/dev/null 2>&1; then
  echo false
  exit 0
fi

source="$(tlp-stat -s 2>/dev/null | awk -F'= ' '/Power source/ {print $2; exit}' || true)"
[ "$source" = "AC" ] && echo true || echo false
