#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
STATE_FILE="$ROOT_DIR/settings/state.json"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"

ensure_state() {
  [[ -f "$STATE_FILE" ]] || printf '{}\n' > "$STATE_FILE"
}

pick() {
  local p="$1"
  shift
  printf '%s\n' "$@" | rofi -dmenu -i -p "$p" -theme "$HOME/.config/rofi/actions.rasi" || true
}

ensure_state

while true; do
  action="$(pick 'App Routing' 'Add Rule' 'Remove Rule' 'List Rules' 'Back')"
  [[ -n "$action" ]] || exit 0
  case "$action" in
    'Add Rule')
      app="$(printf '' | rofi -dmenu -p 'App name/class' -theme "$HOME/.config/rofi/actions.rasi" || true)"
      [[ -n "$app" ]] || continue
      priority="$(pick 'Priority' critical high normal low silent)"
      route="$(pick 'Route' both popup action-center mute)"
      sound="$(pick 'Sound' message system critical none)"
      sink="$(printf 'default\n' | rofi -dmenu -p 'Audio sink (default or sink name)' -theme "$HOME/.config/rofi/actions.rasi" || true)"
      ws="$(printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nspecial:sidepanel\n' | rofi -dmenu -p 'Workspace target' -theme "$HOME/.config/rofi/actions.rasi" || true)"
      [[ -n "$priority" && -n "$route" && -n "$sound" && -n "$sink" && -n "$ws" ]] || continue
      tmp="$(mktemp)"
      jq --arg app "$app" --arg priority "$priority" --arg route "$route" --arg sound "$sound" --arg sink "$sink" --arg ws "$ws" '
        .app_routing.rules = ((.app_routing.rules // []) + [{app:$app,priority:$priority,route:$route,sound:$sound,audio_sink:$sink,workspace:$ws}])
      ' "$STATE_FILE" > "$tmp"
      mv "$tmp" "$STATE_FILE"
      "$SETTINGSCTL" apply app-routing
      ;;
    'Remove Rule')
      rows="$("$SETTINGSCTL" list | jq -r '.app_routing.rules | to_entries[] | "\(.key)|\(.value.app) [\(.value.priority)] -> \(.value.route) ws:\(.value.workspace)"' || true)"
      [[ -n "$rows" ]] || continue
      selected="$(printf '%s\n' "$rows" | rofi -dmenu -i -p 'Remove rule' -theme "$HOME/.config/rofi/actions.rasi" || true)"
      [[ -n "$selected" ]] || continue
      idx="${selected%%|*}"
      tmp="$(mktemp)"
      jq --argjson idx "$idx" '.app_routing.rules |= (to_entries | map(select(.key != $idx)) | map(.value))' "$STATE_FILE" > "$tmp"
      mv "$tmp" "$STATE_FILE"
      "$SETTINGSCTL" apply app-routing
      ;;
    'List Rules')
      text="$("$SETTINGSCTL" list | jq -r '.app_routing.rules[] | "- \(.app): priority=\(.priority), route=\(.route), sound=\(.sound), sink=\(.audio_sink), workspace=\(.workspace)"' || true)"
      [[ -n "$text" ]] || text='No rules found'
      kitty -e sh -lc "printf '%s\n' \"$text\"; read -r -p 'Press enter to close'"
      ;;
    'Back') exit 0 ;;
  esac
done
