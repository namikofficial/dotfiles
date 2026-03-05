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
  "Toggle Wi-Fi"
  "Toggle Network Applet"
  "Toggle Bluetooth"
  "Workspace Overview"
  "Audio Mixer"
  "Bluetooth Manager"
  "Network Manager"
  "Toggle Mic Mute"
  "AI Helper Menu"
  "AI Shell Command"
  "AI Clipboard Summary"
  "System Update"
  "Next Wallpaper"
  "Screenshot Area"
  "Screenshot Full"
  "OCR Area -> Clipboard"
  "Toggle Screen Record"
  "Toggle Layout (Master/Dwindle)"
  "Toggle Floating Grid"
  "Toggle Widget Panel (quick)"
  "Toggle Desktop Widgets"
  "Toggle Panel Engine"
  "Toggle Panel Visibility"
  "Restart Waybar"
  "Copy Notification Summary"
  "Show Keybind Cheat Sheet"
  "Apply Theme Pass"
  "Pick Color"
  "Toggle Night Light"
  "Toggle Notifications"
  "Toggle DND"
  "Clear All Notifications"
  "Power Saver Profile"
  "Performance Profile"
  "System Monitor"
  "Lock Screen"
  "Cycle Dynamic Layout (4 modes)"
  "Logs Workspace (9)"
  "Logs Workspace Stack"
  "Toggle Side Panel"
  "Move Window -> Side Panel"
  "Open LocalSend"
  "Open Obsidian"
)

hint_for_index() {
  case "$1" in
    0) echo 'Ctrl+1' ;;
    1) echo 'Ctrl+2' ;;
    2) echo 'Ctrl+3' ;;
    3) echo 'Ctrl+4' ;;
    4) echo 'Ctrl+5' ;;
    5) echo 'Ctrl+6' ;;
    6) echo 'Ctrl+7' ;;
    7) echo 'Ctrl+8' ;;
    8) echo 'Ctrl+9' ;;
    9) echo 'Ctrl+0' ;;
    *) echo '--' ;;
  esac
}

render_menu() {
  local action idx max_width=0 width hint

  for action in "${actions[@]}"; do
    [ "${#action}" -gt "$max_width" ] && max_width="${#action}"
  done

  width=$((max_width + 2))
  [ "$width" -lt 30 ] && width=30
  [ "$width" -gt 56 ] && width=56

  for idx in "${!actions[@]}"; do
    action="${actions[$idx]}"
    [ "${#action}" -gt 56 ] && action="${action:0:53}..."
    hint="$(hint_for_index "$idx")"
    printf '%-*s | quick | %7s\n' "$width" "$action" "$hint"
  done
}

set +e
choice_index="$(
  render_menu | rofi -dmenu -i \
    -no-show-icons \
    -p 'Quick Actions' \
    -mesg 'Ctrl+1..0 quick-launch rows 1-10' \
    -theme "$HOME/.config/rofi/actions.rasi" \
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
[[ "$choice_index" =~ ^[0-9]+$ ]] || exit 0

case "$choice_index" in
  0)
    state="$(nmcli radio wifi)"
    if [ "$state" = "enabled" ]; then
      nmcli radio wifi off
    else
      nmcli radio wifi on
    fi
    ;;
  1) ~/.config/hypr/scripts/nm-applet-toggle.sh ;;
  2)
    state="$(bluetoothctl show | awk '/Powered:/ {print $2}')"
    if [ "$state" = "yes" ]; then
      bluetoothctl power off
    else
      bluetoothctl power on
    fi
    ;;
  3) ~/.config/hypr/scripts/workspace-overview-toggle.sh ;;
  4) pavucontrol ;;
  5) blueman-manager ;;
  6) nm-connection-editor ;;
  7) ~/.config/hypr/scripts/volume-control.sh mic-mute ;;
  8) ~/.config/hypr/scripts/ai-helper.sh menu ;;
  9) ~/.config/hypr/scripts/ai-helper.sh shell ;;
  10) ~/.config/hypr/scripts/ai-helper.sh clip ;;
  11) kitty -e sh -lc 'yay -Syu; read -r -p "Press enter to close"' ;;
  12) ~/.config/hypr/scripts/set-wallpaper.sh --next ;;
  13) ~/.config/hypr/scripts/screenshot.sh area ;;
  14) ~/.config/hypr/scripts/screenshot.sh full ;;
  15) ~/.config/hypr/scripts/ocr-capture.sh ;;
  16) ~/.config/hypr/scripts/screen-record-toggle.sh ;;
  17) ~/.config/hypr/scripts/layout-switcher.sh toggle ;;
  18) ~/.config/hypr/scripts/layout-switcher.sh allfloat ;;
  19) ~/.config/hypr/scripts/eww-toggle.sh ;;
  20) ~/.config/hypr/scripts/eww-desktop-toggle.sh ;;
  21) ~/.config/hypr/scripts/panel-switch.sh toggle ;;
  22) ~/.config/hypr/scripts/panel-switch.sh toggle-view ;;
  23) ~/.config/hypr/scripts/restart-waybar.sh ;;
  24) ~/.config/hypr/scripts/notification-summary.sh copy ;;
  25) ~/.config/hypr/scripts/hypr-binds.sh ;;
  26) ~/.config/hypr/scripts/theme-pass.sh ;;
  27) hyprpicker -a ;;
  28) ~/.config/hypr/scripts/night-light-toggle.sh ;;
  29) swaync-client -t ;;
  30) swaync-client -d ;;
  31) swaync-client -C ;;
  32) powerprofilesctl set power-saver ;;
  33) powerprofilesctl set performance ;;
  34) kitty -e btop ;;
  35) ~/.config/hypr/scripts/lock.sh ;;
  36) ~/.config/hypr/scripts/layout-switcher.sh cycle ;;
  37) ~/.config/hypr/scripts/logs-workspace.sh open ;;
  38) ~/.config/hypr/scripts/logs-workspace.sh stack ;;
  39) ~/.config/hypr/scripts/sidepanel.sh toggle ;;
  40) ~/.config/hypr/scripts/sidepanel.sh send ;;
  41) flatpak run org.localsend.localsend_app >/dev/null 2>&1 & ;;
  42) obsidian >/dev/null 2>&1 & ;;
  *) exit 0 ;;
esac
