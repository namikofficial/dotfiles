#!/usr/bin/env sh
set -eu

if ! command -v curl >/dev/null 2>&1; then
  echo " --"
  exit 0
fi

out="$(curl -fsS --max-time 2 'https://wttr.in/?format=%t' 2>/dev/null || true)"
if [ -z "$out" ]; then
  echo " --"
  exit 0
fi

# Normalize +19C / -2C output
printf ' %s\n' "$out"
