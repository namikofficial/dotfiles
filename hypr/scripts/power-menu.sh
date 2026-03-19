#!/usr/bin/env sh
set -eu

mode="${1:-full}"

show_compact_menu() {
  choice="$(
    printf '%s\n' \
      "󰌾  Lock" \
      "󰤄  Sleep" \
      "󰒲  Hibernate" \
      "󰍃  Logout" \
      "󰜉  Reboot" \
      "󰐥  Shutdown" \
      "󰑐  Restart Waybar" \
    | rofi -dmenu -i -p "Power" -theme "$HOME/.config/rofi/actions.rasi"
  )"

  case "$choice" in
    "󰌾  Lock") ~/.config/hypr/scripts/lock.sh ;;
    "󰤄  Sleep") systemctl suspend ;;
    "󰒲  Hibernate") systemctl hibernate ;;
    "󰍃  Logout") hyprctl dispatch exit ;;
    "󰜉  Reboot") systemctl reboot ;;
    "󰐥  Shutdown") systemctl poweroff ;;
    "󰑐  Restart Waybar") ~/.config/hypr/scripts/restart-waybar.sh ;;
    *) exit 0 ;;
  esac
}

if [ "$mode" = "compact" ]; then
  show_compact_menu
  exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
  # Toggle behavior: if already open, close it instead of spawning another one.
  if pgrep -x wlogout >/dev/null 2>&1; then
    pkill -x wlogout
    exit 0
  fi

  exec wlogout \
    --layout "$HOME/.config/wlogout/layout" \
    --css "$HOME/.config/wlogout/style.css" \
    --buttons-per-row 3 \
    --column-spacing 12 \
    --row-spacing 12
fi

show_compact_menu
