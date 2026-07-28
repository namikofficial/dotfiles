#!/usr/bin/env sh
# Brightness control — direct brightnessctl.
# NoxFlow island provides the visual OSD; this script only changes backlight.
set -eu

action="${1:-}"

usage() {
  echo "usage: $0 [up|down|menu]" >&2
}

[ -n "$action" ] || { usage; exit 1; }

if [ "$action" = "menu" ]; then
  choice="$(
    printf '%s\n' "100%" "80%" "65%" "50%" "35%" "20%" |
      rofi -dmenu -i -p "Brightness" -theme "$HOME/.config/rofi/actions.rasi" || true
  )"
  [ -n "$choice" ] || exit 0
  brightnessctl -e4 -n2 set "$choice"
  exit 0
fi

case "$action" in
  up) brightnessctl -e4 -n2 set 5%+ ;;
  down) brightnessctl -e4 -n2 set 5%- ;;
  *)
    usage
    exit 1
    ;;
esac
