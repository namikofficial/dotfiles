#!/usr/bin/env bash
set -euo pipefail

count=0

if command -v checkupdates >/dev/null 2>&1; then
  pac_count="$( (checkupdates 2>/dev/null || true) | wc -l | tr -d ' ')"
  [[ "$pac_count" =~ ^[0-9]+$ ]] || pac_count=0
  count=$((count + pac_count))
fi

if command -v paru >/dev/null 2>&1; then
  aur_count="$( (paru -Qua 2>/dev/null || true) | wc -l | tr -d ' ')"
  [[ "$aur_count" =~ ^[0-9]+$ ]] || aur_count=0
  count=$((count + aur_count))
elif command -v yay >/dev/null 2>&1; then
  aur_count="$( (yay -Qua 2>/dev/null || true) | wc -l | tr -d ' ')"
  [[ "$aur_count" =~ ^[0-9]+$ ]] || aur_count=0
  count=$((count + aur_count))
fi

if (( count > 0 )); then
  text="$count"
  tooltip="$count updates available"
else
  text="0"
  tooltip="System up to date"
fi

printf '{"count":%d,"text":"%s","tooltip":"%s"}\n' "$count" "$text" "$tooltip"
