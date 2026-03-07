#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"

path="${1:-}"
delta="${2:-}"
section="${3:-all}"

[[ -n "$path" && -n "$delta" ]] || {
  echo "Usage: adjust.sh <path> <delta> [section]" >&2
  exit 1
}

current="$($SETTINGSCTL get "$path")"

if [[ "$current" =~ ^-?[0-9]+$ ]] && [[ "$delta" =~ ^-?[0-9]+$ ]]; then
  next=$((current + delta))
else
  next="$(awk -v c="$current" -v d="$delta" 'BEGIN { printf "%.2f", c + d }')"
fi

$SETTINGSCTL set "$path" "$next"
$SETTINGSCTL apply "$section"
