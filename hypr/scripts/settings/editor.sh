#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"

prompt_value() {
  local title="$1" current="$2"
  printf '%s\n' "$current" | rofi -dmenu -p "$title" -theme "$HOME/.config/rofi/actions.rasi" || true
}

while true; do
  choice="$(cat <<MENU | rofi -dmenu -i -p 'Settings Editor' -theme "$HOME/.config/rofi/actions.rasi" || true
Toggle Notification Sounds|toggle notifications.sounds.enabled|sounds
Set Notification Timeout|set notifications.timeout|notifications
Set Action Center Width|set action_center.width|action-center
Set Action Center Height|set action_center.height|action-center
Set Lock Blur Passes|set lock_screen.blur_passes|lock-screen
Set Lock Brightness|set lock_screen.brightness|lock-screen
Set Wallpaper Interval (minutes)|set wallpaper.rotate_interval_minutes|wallpaper
Toggle Wallpaper Rotate|toggle wallpaper.rotate_enabled|wallpaper
Restore Waybar Panel|apply panel|panel
Set Power Profile (power-saver/balanced/performance)|set-string power.default_profile|power
Set Keyboard Layout|set-string input.kb_layout|input
Toggle Touchpad Natural Scroll|toggle input.touchpad_natural_scroll|input
Toggle Workspace Swipe|toggle input.workspace_swipe|input
Toggle Clipboard History|toggle privacy.clipboard_history_enabled|privacy
Set Default Browser Desktop ID|set-string default_apps.browser_desktop|default-apps
Set Default Image Viewer Desktop ID|set-string default_apps.image_viewer_desktop|default-apps
Back|back|none
MENU
)"

  [[ -n "$choice" ]] || exit 0
  action="${choice#*|}"; action="${action%%|*}"
  path="${choice#*|}"; path="${path#*|}"; path="${path%%|*}"
  section="${choice##*|}"

  if [[ "$action" == "back" ]]; then
    exit 0
  fi

  if [[ "$action" == "toggle" ]]; then
    "$SETTINGSCTL" toggle "$path"
    "$SETTINGSCTL" apply "$section"
    continue
  fi

  if [[ "$action" == "apply" ]]; then
    "$SETTINGSCTL" apply "$section"
    continue
  fi

  if [[ "$action" == "set" || "$action" == "set-string" ]]; then
    current="$("$SETTINGSCTL" get "$path" || true)"
    value="$(prompt_value "$path" "$current")"
    [[ -n "$value" ]] || continue
    if [[ "$action" == "set" ]]; then
      "$SETTINGSCTL" set "$path" "$value"
    else
      "$SETTINGSCTL" set-string "$path" "$value"
    fi
    "$SETTINGSCTL" apply "$section"
  fi
done
