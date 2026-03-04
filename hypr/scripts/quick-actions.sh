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
󰚩  AI Helper Menu
󰘦  AI Shell Command
󱞁  AI Clipboard Summary
󰚰  System Update
󰸉  Next Wallpaper
󰋊  Screenshot Area
󰍹  Screenshot Full
󰑊  Toggle Screen Record
󰍹  Toggle Layout (Master/Dwindle)
󰍸  Toggle Floating Grid
󰫌  Toggle Widget Panel
󰖨  Restart Waybar
󰸌  Apply Theme Pass
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
    if [ "$state" = "enabled" ]; then
      nmcli radio wifi off
    else
      nmcli radio wifi on
    fi
    ;;
  "󰂯  Toggle Bluetooth")
    state="$(bluetoothctl show | awk '/Powered:/ {print $2}')"
    if [ "$state" = "yes" ]; then
      bluetoothctl power off
    else
      bluetoothctl power on
    fi
    ;;
  "󰍹  Workspace Overview") ~/.config/hypr/scripts/workspace-overview.sh ;;
  "󰕾  Audio Mixer") pavucontrol ;;
  "󰒓  Bluetooth Manager") blueman-manager ;;
  "󰍜  Network Manager") nm-connection-editor ;;
  "󰍉  Toggle Mic Mute") wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
  "󰚩  AI Helper Menu") ~/.config/hypr/scripts/ai-helper.sh menu ;;
  "󰘦  AI Shell Command") ~/.config/hypr/scripts/ai-helper.sh shell ;;
  "󱞁  AI Clipboard Summary") ~/.config/hypr/scripts/ai-helper.sh clip ;;
  "󰚰  System Update") kitty -e sh -lc 'yay -Syu; read -r -p "Press enter to close"' ;;
  "󰸉  Next Wallpaper") ~/.config/hypr/scripts/set-wallpaper.sh --next ;;
  "󰋊  Screenshot Area") ~/.config/hypr/scripts/screenshot.sh area ;;
  "󰍹  Screenshot Full") ~/.config/hypr/scripts/screenshot.sh full ;;
  "󰑊  Toggle Screen Record") ~/.config/hypr/scripts/screen-record-toggle.sh ;;
  "󰍹  Toggle Layout (Master/Dwindle)") ~/.config/hypr/scripts/layout-switcher.sh toggle ;;
  "󰍸  Toggle Floating Grid") ~/.config/hypr/scripts/layout-switcher.sh allfloat ;;
  "󰫌  Toggle Widget Panel") ~/.config/hypr/scripts/eww-toggle.sh ;;
  "󰖨  Restart Waybar") sh -lc 'pkill -x waybar >/dev/null 2>&1 || true; waybar >/dev/null 2>&1 &' ;;
  "󰸌  Apply Theme Pass") ~/.config/hypr/scripts/theme-pass.sh ;;
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
