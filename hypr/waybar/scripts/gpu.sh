#!/usr/bin/env sh
set -eu

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo " n/a"
  exit 0
fi

line="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"

if [ -z "$line" ]; then
  echo " n/a"
  exit 0
fi

util="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $1); print $1}')"
temp="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $2); print $2}')"
used="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $3); print $3}')"
total="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $4); print $4}')"

printf '󰢮 %s%% %sC %s/%sM\n' "$util" "$temp" "$used" "$total"
