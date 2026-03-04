#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
pid_file="${state_dir}/rofi-actions.pid"
other_pid_file="${state_dir}/rofi-launcher.pid"
mkdir -p "$state_dir"

stop_if_running() {
  local file="$1"
  [ -f "$file" ] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$file"
    return 0
  fi
  rm -f "$file"
  return 1
}

# Same shortcut closes this menu.
if stop_if_running "$pid_file"; then
  exit 0
fi

# If launcher is open, close it first.
stop_if_running "$other_pid_file" || true

actions=(
  "󰖩  Toggle Wi-Fi"
  "󰖪  Toggle Network Applet"
  "󰂯  Toggle Bluetooth"
  "󰍹  Workspace Overview"
  "󰕾  Audio Mixer"
  "󰒓  Bluetooth Manager"
  "󰍜  Network Manager"
  "󰍉  Toggle Mic Mute"
  "󰚩  AI Helper Menu"
  "󰘦  AI Shell Command"
  "󱞁  AI Clipboard Summary"
  "󰚰  System Update"
  "󰸉  Next Wallpaper"
  "󰋊  Screenshot Area"
  "󰍹  Screenshot Full"
  "󰓝  OCR Area -> Clipboard"
  "󰑊  Toggle Screen Record"
  "󰍹  Toggle Layout (Master/Dwindle)"
  "󰍸  Toggle Floating Grid"
  "󰫌  Toggle Widget Panel (quick)"
  "󰫌  Toggle Desktop Widgets"
  "󰕮  Toggle Panel Engine"
  "󰕮  Toggle Panel Visibility"
  "󰖨  Restart Waybar"
  "󰏢  Copy Notification Summary"
  "󰸌  Apply Theme Pass"
  "󰏘  Pick Color"
  "󰖔  Toggle Night Light"
  "󰓃  Toggle Notifications"
  "󱐋  Toggle DND"
  "󰆴  Clear All Notifications"
  "󰾆  Power Saver Profile"
  "󱐤  Performance Profile"
  "󰒓  System Monitor"
  "󰌾  Lock Screen"
)

render_menu() {
  local action hint idx=0
  for action in "${actions[@]}"; do
    if [ "${#action}" -gt 52 ]; then
      action="${action:0:49}..."
    fi

    case "$idx" in
      0) hint='Ctrl+1' ;;
      1) hint='Ctrl+2' ;;
      2) hint='Ctrl+3' ;;
      3) hint='Ctrl+4' ;;
      4) hint='Ctrl+5' ;;
      5) hint='Ctrl+6' ;;
      6) hint='Ctrl+7' ;;
      7) hint='Ctrl+8' ;;
      8) hint='Ctrl+9' ;;
      9) hint='Ctrl+0' ;;
      *) hint='Ctrl+1..0' ;;
    esac

    printf '%s\t%s\n' "$action" "$hint"
    idx=$((idx + 1))
  done
}

set +e
choice_index="$(
  render_menu | rofi -dmenu -i \
    -no-show-icons \
    -p 'Quick Actions' \
    -mesg 'Quick run with Ctrl+1..0 (or Enter)' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -display-columns 1,2 \
    -display-column-separator '\t' \
    -kb-select-1 'Control+1,Super+1' \
    -kb-select-2 'Control+2,Super+2' \
    -kb-select-3 'Control+3,Super+3' \
    -kb-select-4 'Control+4,Super+4' \
    -kb-select-5 'Control+5,Super+5' \
    -kb-select-6 'Control+6,Super+6' \
    -kb-select-7 'Control+7,Super+7' \
    -kb-select-8 'Control+8,Super+8' \
    -kb-select-9 'Control+9,Super+9' \
    -kb-select-10 'Control+0,Super+0' \
    -kb-cancel 'Escape,Control+g,Super+a,Super+slash' \
    -format 'i' \
    -pid "$pid_file"
)"
rofi_status=$?
set -e

rm -f "$pid_file"
[ "$rofi_status" -eq 0 ] || exit 0
[ -n "$choice_index" ] || exit 0

if ! [[ "$choice_index" =~ ^[0-9]+$ ]]; then
  exit 0
fi

choice="${actions[$choice_index]:-}"
[ -n "$choice" ] || exit 0

case "$choice" in
  "󰖩  Toggle Wi-Fi")
    state="$(nmcli radio wifi)"
    if [ "$state" = "enabled" ]; then
      nmcli radio wifi off
    else
      nmcli radio wifi on
    fi
    ;;
  "󰖪  Toggle Network Applet") ~/.config/hypr/scripts/nm-applet-toggle.sh ;;
  "󰂯  Toggle Bluetooth")
    state="$(bluetoothctl show | awk '/Powered:/ {print $2}')"
    if [ "$state" = "yes" ]; then
      bluetoothctl power off
    else
      bluetoothctl power on
    fi
    ;;
  "󰍹  Workspace Overview") ~/.config/hypr/scripts/workspace-overview-toggle.sh ;;
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
  "󰓝  OCR Area -> Clipboard") ~/.config/hypr/scripts/ocr-capture.sh ;;
  "󰑊  Toggle Screen Record") ~/.config/hypr/scripts/screen-record-toggle.sh ;;
  "󰍹  Toggle Layout (Master/Dwindle)") ~/.config/hypr/scripts/layout-switcher.sh toggle ;;
  "󰍸  Toggle Floating Grid") ~/.config/hypr/scripts/layout-switcher.sh allfloat ;;
  "󰫌  Toggle Widget Panel (quick)") ~/.config/hypr/scripts/eww-toggle.sh ;;
  "󰫌  Toggle Desktop Widgets") ~/.config/hypr/scripts/eww-desktop-toggle.sh ;;
  "󰕮  Toggle Panel Engine") ~/.config/hypr/scripts/panel-switch.sh toggle ;;
  "󰕮  Toggle Panel Visibility") ~/.config/hypr/scripts/panel-switch.sh toggle-view ;;
  "󰖨  Restart Waybar") ~/.config/hypr/scripts/restart-waybar.sh ;;
  "󰏢  Copy Notification Summary") ~/.config/hypr/scripts/notification-summary.sh copy ;;
  "󰸌  Apply Theme Pass") ~/.config/hypr/scripts/theme-pass.sh ;;
  "󰏘  Pick Color") hyprpicker -a ;;
  "󰖔  Toggle Night Light") ~/.config/hypr/scripts/night-light-toggle.sh ;;
  "󰓃  Toggle Notifications") swaync-client -t ;;
  "󱐋  Toggle DND") swaync-client -d ;;
  "󰆴  Clear All Notifications") swaync-client -C ;;
  "󰾆  Power Saver Profile") powerprofilesctl set power-saver ;;
  "󱐤  Performance Profile") powerprofilesctl set performance ;;
  "󰒓  System Monitor") kitty -e btop ;;
  "󰌾  Lock Screen") ~/.config/hypr/scripts/lock.sh ;;
  *) exit 0 ;;
esac
