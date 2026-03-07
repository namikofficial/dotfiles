#!/usr/bin/env sh
set -eu

kind="${1:-default}"
override_id="${2:-}"
settings_file="$HOME/Documents/code/dotfiles/settings/defaults.json"
state_file="$HOME/Documents/code/dotfiles/settings/state.json"

if ! command -v canberra-gtk-play >/dev/null 2>&1; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [ -f "$settings_file" ] && [ -f "$state_file" ]; then
  enabled="$(jq -s '.[0] * .[1] | .notifications.sounds.enabled' "$settings_file" "$state_file" 2>/dev/null || echo true)"
else
  enabled=true
fi

[ "$enabled" = "true" ] || exit 0

if [ -n "$override_id" ]; then
  canberra-gtk-play -i "$override_id" -d swaync >/dev/null 2>&1 || true
  exit 0
fi

if [ -f "$settings_file" ] && [ -f "$state_file" ]; then
  sound_id="$(jq -r -s --arg kind "$kind" '.[0] * .[1] | .notifications.sounds[$kind] // empty' "$settings_file" "$state_file" 2>/dev/null || true)"
else
  sound_id=""
fi

if [ -n "$sound_id" ]; then
  canberra-gtk-play -i "$sound_id" -d swaync >/dev/null 2>&1 || true
  exit 0
fi

case "$kind" in
  critical) sound_id="dialog-warning" ;;
  message) sound_id="message-new-instant" ;;
  system) sound_id="service-login" ;;
  *) sound_id="message" ;;
esac

canberra-gtk-play -i "$sound_id" -d swaync >/dev/null 2>&1 || true
