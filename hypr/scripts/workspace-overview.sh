#!/usr/bin/env sh
set -eu

if ! command -v hyprctl >/dev/null 2>&1; then
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  hyprctl dispatch workspace e+1
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  hyprctl dispatch workspace e+1
  exit 0
fi

clients_json="$(hyprctl -j clients 2>/dev/null || echo '[]')"

entries="$({
  for ws in 1 2 3 4 5 6 7 8 9 10; do
    count="$(printf '%s' "$clients_json" | jq --argjson ws "$ws" '[.[] | select(.workspace.id == $ws)] | length')"
    printf '%s\tworkspace\t󰍹  Workspace %s  (%s windows)\n' "$ws" "$ws" "$count"
  done

  printf '%s' "$clients_json" | jq -r '
    map(select(.workspace.id > 0))
    | sort_by(.workspace.id, .address)
    | .[]
    | "\(.workspace.id)\twindow\t󰖯  [\(.workspace.id)] \((.class // \"app\")) - \((.title // \"untitled\"))\t\(.address)"
  '
} | awk 'NF' | sort -n -k1,1)"

[ -n "$entries" ] || exit 0

choice="$(printf '%s\n' "$entries" | rofi -dmenu -i \
  -p 'Workspace Overview' \
  -theme "$HOME/.config/rofi/launcher.rasi" \
  -display-columns 3 \
  -display-column-separator '\t')"

[ -n "$choice" ] || exit 0

workspace_id="$(printf '%s' "$choice" | awk -F '\t' '{print $1}')"
entry_type="$(printf '%s' "$choice" | awk -F '\t' '{print $2}')"
window_addr="$(printf '%s' "$choice" | awk -F '\t' '{print $4}')"

[ -n "$workspace_id" ] || exit 0

hyprctl dispatch workspace "$workspace_id" >/dev/null 2>&1 || true

if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
  hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
fi
