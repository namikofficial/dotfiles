#!/usr/bin/env bash
set -euo pipefail

path="${1:-}"
SETTINGSCTL="$HOME/.config/hypr/scripts/settingsctl"

get_setting() {
  "$SETTINGSCTL" get "$1" 2>/dev/null || echo "n/a"
}

case "$path" in
  notifications.timeout)
    v="$(get_setting notifications.timeout)"
    echo "${v}s"
    ;;
  notifications.sounds.enabled)
    v="$(get_setting notifications.sounds.enabled)"
    [[ "$v" == "true" ]] && echo "ON" || echo "OFF"
    ;;
  action_center.width)
    v="$(get_setting action_center.width)"
    echo "${v}px"
    ;;
  lock_screen.blur_passes)
    get_setting lock_screen.blur_passes
    ;;
  wallpaper.rotate_enabled)
    v="$(get_setting wallpaper.rotate_enabled)"
    [[ "$v" == "true" ]] && echo "ON" || echo "OFF"
    ;;
  panel.engine)
    get_setting panel.engine
    ;;
  power.default_profile)
    get_setting power.default_profile
    ;;
  input.touchpad_natural_scroll)
    v="$(get_setting input.touchpad_natural_scroll)"
    [[ "$v" == "true" ]] && echo "ON" || echo "OFF"
    ;;
  machine.profile)
    get_setting machine.profile
    ;;
  privacy.clipboard_history_enabled)
    v="$(get_setting privacy.clipboard_history_enabled)"
    [[ "$v" == "true" ]] && echo "ON" || echo "OFF"
    ;;
  dnd)
    if [ -x "$HOME/.config/hypr/scripts/notif-peek.sh" ]; then
      "$HOME/.config/hypr/scripts/notif-peek.sh" dnd
    elif command -v swaync-client >/dev/null 2>&1; then
      v="$(swaync-client -D 2>/dev/null || echo false)"
      [[ "$v" == "true" ]] && echo "ON" || echo "OFF"
    else
      echo "n/a"
    fi
    ;;
  panel.visible)
    if [ -x "$HOME/.config/hypr/scripts/panel-switch.sh" ]; then
      v="$($HOME/.config/hypr/scripts/panel-switch.sh status 2>/dev/null || echo unknown)"
      echo "$v"
    else
      echo "n/a"
    fi
    ;;
  night.light)
    if pgrep -x hyprsunset >/dev/null 2>&1; then
      echo "ON"
    else
      echo "OFF"
    fi
    ;;
  notifications.count)
    if [ -x "$HOME/.config/hypr/scripts/notif-peek.sh" ]; then
      "$HOME/.config/hypr/scripts/notif-peek.sh" count
    elif command -v swaync-client >/dev/null 2>&1; then
      c="$(swaync-client -c 2>/dev/null || echo 0)"
      echo "$c"
    else
      echo "n/a"
    fi
    ;;
  *)
    echo "n/a"
    ;;
esac
