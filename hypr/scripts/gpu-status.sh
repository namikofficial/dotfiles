#!/usr/bin/env bash
set -euo pipefail

watch_mode=0
interval=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--watch)
      watch_mode=1
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        interval="$2"
        shift
      fi
      ;;
    -h|--help)
      cat <<'EOF'
Usage: gpu-status [--watch [seconds]]

Shows one-shot Intel + NVIDIA GPU status.
Use --watch to refresh continuously.
EOF
      exit 0
      ;;
  esac
  shift
done

nvidia_status() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA: nvidia-smi not found"
    return
  fi

  local line
  line="$(nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
  if [[ -z "$line" ]]; then
    echo "NVIDIA: unavailable"
    return
  fi

  IFS=',' read -r name util mem temp power <<<"$line"
  name="$(echo "$name" | sed 's/^ *//;s/ *$//')"
  util="$(echo "$util" | sed 's/^ *//;s/ *$//')"
  mem="$(echo "$mem" | sed 's/^ *//;s/ *$//')"
  temp="$(echo "$temp" | sed 's/^ *//;s/ *$//')"
  power="$(echo "$power" | sed 's/^ *//;s/ *$//')"

  echo "NVIDIA: ${name} | util ${util}% | mem ${mem}% | temp ${temp}C | power ${power}W"
}

intel_status() {
  if ! command -v intel_gpu_top >/dev/null 2>&1; then
    echo "INTEL: intel_gpu_top not found"
    return
  fi

  local json
  json="$(timeout 2 intel_gpu_top -J -s 1000 2>/dev/null || true)"
  if [[ -z "$json" ]]; then
    echo "INTEL: unavailable"
    return
  fi

  local render video blitter rc6 gpupower
  render="$(printf '%s\n' "$json" | awk '/"Render\/3D"/{f=1;next} f&&/"busy"/{gsub(/[^0-9.]/,"",$2); print $2; exit}')"
  blitter="$(printf '%s\n' "$json" | awk '/"Blitter"/{f=1;next} f&&/"busy"/{gsub(/[^0-9.]/,"",$2); print $2; exit}')"
  video="$(printf '%s\n' "$json" | awk '/"Video"/{f=1;next} f&&/"busy"/{gsub(/[^0-9.]/,"",$2); print $2; exit}')"
  rc6="$(printf '%s\n' "$json" | awk '/"rc6"/{f=1;next} f&&/"value"/{gsub(/[^0-9.]/,"",$2); print $2; exit}')"
  gpupower="$(printf '%s\n' "$json" | awk '/"power"/{f=1;next} f&&/"GPU"/{gsub(/[^0-9.]/,"",$2); print $2; exit}')"

  [[ -z "$render" ]] && render="n/a"
  [[ -z "$blitter" ]] && blitter="n/a"
  [[ -z "$video" ]] && video="n/a"
  [[ -z "$rc6" ]] && rc6="n/a"
  [[ -z "$gpupower" ]] && gpupower="n/a"

  echo "INTEL: render ${render}% | blitter ${blitter}% | video ${video}% | rc6 ${rc6}% | gpu ${gpupower}W"
}

print_status() {
  echo "GPU STATUS $(date '+%F %T')"
  nvidia_status
  intel_status
}

if [[ "$watch_mode" -eq 1 ]]; then
  while true; do
    clear
    print_status
    sleep "$interval"
  done
else
  print_status
fi
