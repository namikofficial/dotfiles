#!/usr/bin/env sh
set -eu

action="${1:-}"

usage() {
  echo "usage: $0 [up|down|menu]" >&2
}

[ -n "$action" ] || {
  usage
  exit 1
}

if command -v lightctl >/dev/null 2>&1; then
  case "$action" in
    up) lightctl up ;;
    down) lightctl down ;;
    menu) ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

if command -v swayosd-client >/dev/null 2>&1; then
  case "$action" in
    up) swayosd-client --brightness raise ;;
    down) swayosd-client --brightness lower ;;
    menu) ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

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
