#!/usr/bin/env sh
set -eu

total="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
avail="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)"

if [ -z "$total" ] || [ -z "$avail" ] || [ "$total" -le 0 ]; then
  jq -cn --arg text "RAM --" --arg tooltip "Memory unavailable" '{text:$text, tooltip:$tooltip}'
  exit 0
fi

used=$((total - avail))
pct=$((100 * used / total))
used_gb=$((used / 1024 / 1024))
total_gb=$((total / 1024 / 1024))
cache_mb="$(awk '/^Cached:/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null || echo 0)"

tooltip="$(printf 'RAM %s%%\nUsed %sG / %sG\nCache %s MB\n\nClick: open btop' "$pct" "$used_gb" "$total_gb" "$cache_mb")"
jq -cn --arg text "RAM ${pct}%" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'
