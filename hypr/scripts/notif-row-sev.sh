#!/usr/bin/env bash
set -euo pipefail

idx="${1:-0}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

if ! command -v jq >/dev/null 2>&1 || [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  echo "info"
  exit 0
fi

jq -r --argjson i "$idx" '
  .events as $e
  | if (($e|length) <= $i) then "info"
    else ($e[$i].severity // "info")
    end
' "$state_file"
