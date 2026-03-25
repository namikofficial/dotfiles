#!/usr/bin/env bash
set -euo pipefail

mode="${1:-custom}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

mkdir -p "$(dirname "$state_file")"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  printf '{"mode":"custom","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}' > "$state_file"
fi

if [ "$mode" = "toggle" ]; then
  current="$(jq -r '.mode // "custom"' "$state_file")"
  if [ "$current" = "custom" ]; then
    mode="swaync"
  else
    mode="custom"
  fi
fi

case "$mode" in
  custom)
    # Custom mode: only Eww/custom pipeline, no native popup daemon.
    pkill -x swaync >/dev/null 2>&1 || true
    pkill -x mako >/dev/null 2>&1 || true
    pkill -x dunst >/dev/null 2>&1 || true
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop swaync.service >/dev/null 2>&1 || true
      systemctl --user stop dunst.service >/dev/null 2>&1 || true
      systemctl --user stop mako.service >/dev/null 2>&1 || true
    fi
    pkill -f "$HOME/.config/hypr/scripts/notif-bridge-dbus.sh" >/dev/null 2>&1 || true
    pkill -f "$HOME/.config/hypr/scripts/notif-toast-daemon.sh" >/dev/null 2>&1 || true
    if [ -x "$HOME/.config/hypr/scripts/notif-bridge-dbus.sh" ]; then
      "$HOME/.config/hypr/scripts/notif-bridge-dbus.sh" >/dev/null 2>&1 &
    fi
    if [ -x "$HOME/.config/hypr/scripts/notif-toast-daemon.sh" ]; then
      "$HOME/.config/hypr/scripts/notif-toast-daemon.sh" >/dev/null 2>&1 &
    fi
    if command -v eww >/dev/null 2>&1; then
      if ! eww --config "$HOME/.config/eww" ping >/dev/null 2>&1; then
        eww --config "$HOME/.config/eww" daemon >/dev/null 2>&1 &
      fi
    fi
    ;;
  swaync)
    pkill -f "$HOME/.config/hypr/scripts/notif-bridge-dbus.sh" >/dev/null 2>&1 || true
    pkill -f "$HOME/.config/hypr/scripts/notif-toast-daemon.sh" >/dev/null 2>&1 || true
    if command -v swaync >/dev/null 2>&1 && ! pgrep -x swaync >/dev/null 2>&1; then
      swaync >/dev/null 2>&1 &
    fi
    if command -v eww >/dev/null 2>&1 && eww --config "$HOME/.config/eww" ping >/dev/null 2>&1; then
      eww --config "$HOME/.config/eww" close notif_center >/dev/null 2>&1 || true
      eww --config "$HOME/.config/eww" close notif_backdrop >/dev/null 2>&1 || true
      eww --config "$HOME/.config/eww" close notif_toast >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "usage: $0 [custom|swaync|toggle]" >&2
    exit 1
    ;;
esac

tmp="$(mktemp)"
jq --arg mode "$mode" '.mode=$mode | .updated_at=(now|todateiso8601)' "$state_file" > "$tmp"
mv "$tmp" "$state_file"
