#!/usr/bin/env sh
set -eu

count=0

if command -v checkupdates >/dev/null 2>&1; then
  count="$(checkupdates 2>/dev/null | wc -l | tr -d ' ')"
elif command -v yay >/dev/null 2>&1; then
  count="$(yay -Qua 2>/dev/null | wc -l | tr -d ' ')"
fi

if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
  printf '󰏗  %s\n' "$count"
else
  echo "󰏖  0"
fi
