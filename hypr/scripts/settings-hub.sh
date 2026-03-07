#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
LAST_FILE="$STATE_DIR/last-settings-section"
mkdir -p "$STATE_DIR"

menu_items() {
  cat <<MENU
Apply All Settings|apply|all
Open Settings Panel (Eww)|eww|none
Open Quick Editor (Rofi)|editor|none
Open App Routing Editor|routing|none
Pick Machine Profile|profile|none
Notifications|apply|notifications
Action Center|apply|action-center
Notification Sounds|apply|sounds
Lock Screen|apply|lock-screen
Wallpaper|apply|wallpaper
Panel|apply|panel
Power|apply|power
Input|apply|input
Startup|apply|startup
Per-App Routing|apply|app-routing
Privacy|apply|privacy
Default Apps|apply|default-apps
Doctor Report|doctor|none
Keybind Conflict Check|keycheck|none
MENU
}

mode="${1:-menu}"

if [[ "$mode" == "last" ]]; then
  if [[ -f "$LAST_FILE" ]]; then
    section="$(cat "$LAST_FILE")"
    "$SETTINGSCTL" apply "$section"
  else
    "$SETTINGSCTL" apply all
  fi
  exit 0
fi

if [[ "$mode" == "quick" ]]; then
  "$SETTINGSCTL" toggle notifications.sounds.enabled
  "$SETTINGSCTL" apply sounds
  exit 0
fi

choice="$(menu_items | rofi -dmenu -i -p 'Settings Hub' -theme "$HOME/.config/rofi/actions.rasi" || true)"
[[ -n "$choice" ]] || exit 0

label="${choice%%|*}"
rest="${choice#*|}"
action="${rest%%|*}"
section="${choice##*|}"
printf '%s\n' "$section" > "$LAST_FILE"

case "$action" in
  apply)
    "$SETTINGSCTL" apply "$section"
    ;;
  editor)
    "$ROOT_DIR/hypr/scripts/settings/editor.sh"
    ;;
  routing)
    "$ROOT_DIR/hypr/scripts/settings/app-routing-editor.sh"
    ;;
  profile)
    "$ROOT_DIR/hypr/scripts/settings/profile-picker.sh"
    ;;
  eww)
    "$ROOT_DIR/hypr/scripts/settings-eww.sh"
    ;;
  doctor)
    kitty -e sh -lc "$SETTINGSCTL doctor; read -r -p 'Press enter to close'"
    ;;
  keycheck)
    kitty -e sh -lc "$SETTINGSCTL keycheck; read -r -p 'Press enter to close'"
    ;;
  *)
    echo "Unknown action: $label" >&2
    ;;
esac
