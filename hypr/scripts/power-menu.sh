#!/usr/bin/env sh
set -eu

mode="${1:-full}"
css_file="$HOME/.config/wlogout/style.css"

if [ "$mode" = "futuristic" ]; then
  mode="full"
  css_file="$HOME/.config/wlogout/style-futuristic.css"
fi

if [ "$mode" = "minimal" ]; then
  mode="full"
  css_file="$HOME/.config/wlogout/style.css"
fi

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
    --css "$css_file" \
    --buttons-per-row 3 \
    --column-spacing 10 \
    --row-spacing 10
fi

show_compact_menu
