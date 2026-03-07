#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"

path="${1:-}"
opts_csv="${2:-}"
section="${3:-all}"

[[ -n "$path" && -n "$opts_csv" ]] || {
  echo "Usage: cycle.sh <path> <opt1,opt2,...> [section]" >&2
  exit 1
}

IFS=',' read -r -a opts <<< "$opts_csv"
current="$($SETTINGSCTL get "$path")"
idx=-1
for i in "${!opts[@]}"; do
  if [[ "${opts[$i]}" == "$current" ]]; then
    idx="$i"
    break
  fi
done

if [[ "$idx" -lt 0 ]]; then
  next="${opts[0]}"
else
  next_idx=$(( (idx + 1) % ${#opts[@]} ))
  next="${opts[$next_idx]}"
fi

$SETTINGSCTL set-string "$path" "$next"
$SETTINGSCTL apply "$section"
