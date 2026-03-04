#!/usr/bin/env sh
set -eu

if command -v wlogout >/dev/null 2>&1; then
  exec wlogout
fi

choice="$(
  printf '%s\n' \
    "󰌾  Lock" \
    "󰍃  Logout" \
    "󰜉  Reboot" \
    "󰐥  Shutdown" \
  | rofi -dmenu -i -p "Power" -theme "$HOME/.config/rofi/actions.rasi"
)"
case "$choice" in
  "󰌾  Lock") ~/.config/hypr/scripts/lock.sh ;;
  "󰍃  Logout") hyprctl dispatch exit ;;
  "󰜉  Reboot") systemctl reboot ;;
  "󰐥  Shutdown") systemctl poweroff ;;
  *) exit 0 ;;
esac
