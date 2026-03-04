#!/usr/bin/env sh
set -eu

choice="$(
rofi -dmenu -i -p 'Quick Actions' -theme "$HOME/.config/rofi/actions.rasi" <<'MENU'
󰖩  Toggle Wi-Fi
󰂯  Toggle Bluetooth
󰍹  Workspace Overview
󰕾  Audio Mixer
󰒓  Bluetooth Manager
󰍜  Network Manager
󰍉  Toggle Mic Mute
󰚰  System Update
󰸉  Next Wallpaper
󰋊  Screenshot Area
󰍹  Screenshot Full
󰑊  Toggle Screen Record
󰏘  Pick Color
󰖔  Toggle Night Light
󰓃  Toggle Notifications
󱐋  Toggle DND
󰾆  Power Saver Profile
󱐤  Performance Profile
󰒓  System Monitor
󰌾  Lock Screen
MENU
)"

case "$choice" in
  "󰖩  Toggle Wi-Fi")
    state="$(nmcli radio wifi)"
    [ "$state" = "enabled" ] && nmcli radio wifi off || nmcli radio wifi on
    ;;
  "󰂯  Toggle Bluetooth")
    state="$(bluetoothctl show | awk '/Powered:/ {print $2}')"
    [ "$state" = "yes" ] && bluetoothctl power off || bluetoothctl power on
    ;;
  "󰍹  Workspace Overview") ~/.config/hypr/scripts/workspace-overview.sh ;;
  "󰕾  Audio Mixer") pavucontrol ;;
  "󰒓  Bluetooth Manager") blueman-manager ;;
  "󰍜  Network Manager") nm-connection-editor ;;
  "󰍉  Toggle Mic Mute") wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
  "󰚰  System Update") kitty -e sh -lc 'yay -Syu; read -r -p "Press enter to close"' ;;
  "󰸉  Next Wallpaper") ~/.config/hypr/scripts/set-wallpaper.sh --next ;;
  "󰋊  Screenshot Area") ~/.config/hypr/scripts/screenshot.sh area ;;
  "󰍹  Screenshot Full") ~/.config/hypr/scripts/screenshot.sh full ;;
  "󰑊  Toggle Screen Record") ~/.config/hypr/scripts/screen-record-toggle.sh ;;
  "󰏘  Pick Color") hyprpicker -a ;;
  "󰖔  Toggle Night Light") ~/.config/hypr/scripts/night-light-toggle.sh ;;
  "󰓃  Toggle Notifications") swaync-client -t ;;
  "󱐋  Toggle DND") swaync-client -d ;;
  "󰾆  Power Saver Profile") powerprofilesctl set power-saver ;;
  "󱐤  Performance Profile") powerprofilesctl set performance ;;
  "󰒓  System Monitor") kitty -e btop ;;
  "󰌾  Lock Screen") ~/.config/hypr/scripts/lock.sh ;;
  *) exit 0 ;;
esac
