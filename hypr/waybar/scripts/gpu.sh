#!/usr/bin/env sh
set -eu

find_nvidia_gpu() {
  for dev in /sys/bus/pci/devices/*; do
    [ -r "$dev/vendor" ] || continue
    [ -r "$dev/class" ] || continue
    vendor="$(cat "$dev/vendor" 2>/dev/null || true)"
    class="$(cat "$dev/class" 2>/dev/null || true)"
    if [ "$vendor" = "0x10de" ] && [ "${class#0x03}" != "$class" ]; then
      printf '%s\n' "$dev"
      return 0
    fi
  done
  return 1
}

gpu_dev="$(find_nvidia_gpu || true)"
if [ -z "$gpu_dev" ]; then
  echo " n/a"
  exit 0
fi

runtime="unknown"
if [ -r "$gpu_dev/power/runtime_status" ]; then
  runtime="$(cat "$gpu_dev/power/runtime_status" 2>/dev/null || echo unknown)"
fi

# Optional deep polling for active gaming sessions.
if [ "${WAYBAR_GPU_DEEP_POLL:-0}" = "1" ] && [ "$runtime" = "active" ] && command -v nvidia-smi >/dev/null 2>&1; then
  line="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
  if [ -n "$line" ]; then
    util="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $1); print $1}')"
    temp="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $2); print $2}')"
    used="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $3); print $3}')"
    total="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $4); print $4}')"
    printf '󰢮 %s%% %sC %s/%sM\n' "$util" "$temp" "$used" "$total"
    exit 0
  fi
fi

case "$runtime" in
  suspended) echo "󰢮 sleep" ;;
  active) echo "󰢮 active" ;;
  *) echo "󰢮 $runtime" ;;
esac
