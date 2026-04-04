#!/usr/bin/env bash
set -euo pipefail

idx="${1:-0}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

if ! command -v jq >/dev/null 2>&1 || [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  echo ""
  exit 0
fi

jq -r --argjson i "$idx" '
  .events as $e
  | if (($e|length) <= $i) then ""
    else
      ((if ((.selected_index // 0) == $i) then "● " else "○ " end)
      + "[" + ($e[$i].severity // "info") + "] "
      + (($e[$i].title // "untitled") | gsub("\n"; " ") | .[0:72]))
    end
' "$state_file"
