#!/usr/bin/env bash
set -euo pipefail

noxflow_quick_action_labels() {
  cat <<'EOF'
Toggle Wi-Fi
Toggle Bluetooth
Workspace Overview
Audio Mixer
Bluetooth Manager
Toggle Mic Mute
AI Helper Menu
Open AI Workbench
AI Shell Command
AI Clipboard Summary
System Update
Next Wallpaper
Screenshot Area
Screenshot Full
OCR Area -> Clipboard
Toggle Screen Record
Toggle Layout (Master/Dwindle)
Toggle Focused Window Floating
Switch Panel to Wayle
Toggle Panel Engine
Hide Panel
Toggle Panel Visibility
Show/Restore Panel
Copy Notification Summary
Show Keybind Cheat Sheet
Apply Theme Pass
Pick Color
Toggle Night Light
Toggle Notification Center
Toggle Notification DND
Clear Notifications
Power Saver Profile
Performance Profile
System Monitor
Lock Screen
Cycle Layout (Dwindle/Master/Monocle)
Logs Workspace (9)
Logs Workspace Stack
Toggle Sidecar
Move Window -> Sidecar
Open LocalSend
Open Syncthing UI
Syncthing Control Menu
Open Obsidian
Open Terminal
Open Notes
Open Wayle Notification Panel
Open Settings Hub
Open Control Center
Monitor Control
Run Dev Health
Run Dev Health (JSON)
Project Resume
Recover Desktop
Project Profiles
EOF
}

noxflow_quick_action_run() {
  local choice="$1"

  case "$choice" in
    "Toggle Wi-Fi")
      wifi_if="$(iwctl station list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$1 ~ /^(wlan|wlp)/ { print $1; exit }')"
      state="$(iwctl device "$wifi_if" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk -F: '/Powered/ { gsub(/[[:space:]]/, "", $2); print tolower($2); exit }')"
      if [ "$state" = "on" ]; then
        iwctl device "$wifi_if" set-property Powered off
      else
        iwctl device "$wifi_if" set-property Powered on
      fi
      ;;
    "Toggle Bluetooth")
      state="$(bluetoothctl show | awk '/Powered:/ {print $2}')"
      if [ "$state" = "yes" ]; then
        bluetoothctl power off
      else
        bluetoothctl power on
      fi
      ;;
    "Workspace Overview") ~/.config/hypr/scripts/workspace-overview-toggle.sh ;;
    "Audio Mixer") pavucontrol ;;
    "Bluetooth Manager") blueman-manager ;;
    "Toggle Mic Mute") ~/.config/hypr/scripts/volume-control.sh mic-mute ;;
    "AI Helper Menu") ~/.config/hypr/scripts/ai-helper.sh menu ;;
    "Open AI Workbench") ~/.config/hypr/scripts/open-ai-workbench.sh ;;
    "AI Shell Command") ~/.config/hypr/scripts/ai-helper.sh shell ;;
    "AI Clipboard Summary") ~/.config/hypr/scripts/ai-helper.sh clip ;;
    "System Update") ~/.config/hypr/scripts/system-update.sh ;;
    "Next Wallpaper") ~/.config/hypr/scripts/set-wallpaper.sh --next ;;
    "Screenshot Area") ~/.config/hypr/scripts/screenshot.sh area ;;
    "Screenshot Full") ~/.config/hypr/scripts/screenshot.sh full ;;
    "OCR Area -> Clipboard") ~/.config/hypr/scripts/ocr-capture.sh ;;
    "Toggle Screen Record") ~/.config/hypr/scripts/screen-record-toggle.sh ;;
    "Toggle Layout (Master/Dwindle)") ~/.config/hypr/scripts/layout-switcher.sh toggle ;;
    "Toggle Focused Window Floating") ~/.config/hypr/scripts/layout-switcher.sh allfloat ;;
    "Switch Panel to Wayle") ~/.config/hypr/scripts/panel-switch.sh wayle ;;
    "Toggle Panel Engine") ~/.config/hypr/scripts/panel-switch.sh toggle ;;
    "Hide Panel") ~/.config/hypr/scripts/panel-switch.sh hide ;;
    "Toggle Panel Visibility") ~/.config/hypr/scripts/panel-switch.sh toggle-view ;;
    "Show/Restore Panel") ~/.config/hypr/scripts/panel-switch.sh show ;;
    "Copy Notification Summary") ~/.config/hypr/scripts/notification-summary.sh copy ;;
    "Show Keybind Cheat Sheet") ~/.config/hypr/scripts/hypr-binds.sh ;;
    "Apply Theme Pass") ~/.config/hypr/scripts/theme-pass.sh ;;
    "Pick Color") hyprpicker -a ;;
    "Toggle Night Light") ~/.config/hypr/scripts/night-light-toggle.sh ;;
    "Toggle Notification Center") ~/.config/hypr/scripts/notif-center-toggle.sh ;;
    "Toggle Notification DND") ~/.config/hypr/scripts/notif-dnd-toggle.sh ;;
    "Clear Notifications") ~/.config/hypr/scripts/notif-clear.sh ;;
    "Power Saver Profile") powerprofilesctl set power-saver ;;
    "Performance Profile") powerprofilesctl set performance ;;
    "System Monitor") kitty -e btop ;;
    "Lock Screen") ~/.config/hypr/scripts/lock.sh ;;
    "Cycle Layout (Dwindle/Master/Monocle)") ~/.config/hypr/scripts/layout-switcher.sh cycle ;;
    "Logs Workspace (9)") ~/.config/hypr/scripts/logs-workspace.sh open ;;
    "Logs Workspace Stack") ~/.config/hypr/scripts/logs-workspace.sh stack ;;
    "Toggle Sidecar") ~/.config/hypr/scripts/sidepanel.sh toggle ;;
    "Move Window -> Sidecar") ~/.config/hypr/scripts/sidepanel.sh send ;;
    "Open LocalSend") flatpak run org.localsend.localsend_app >/dev/null 2>&1 & ;;
    "Open Syncthing UI") ~/.config/hypr/scripts/open-syncthing.sh ;;
    "Syncthing Control Menu") ~/.config/hypr/scripts/syncthing-control.sh menu ;;
    "Open Obsidian") obsidian >/dev/null 2>&1 & ;;
    "Open Terminal") kitty >/dev/null 2>&1 & ;;
    "Open Notes") ~/.config/hypr/scripts/open-notes.sh ;;
    "Open Wayle Notification Panel") ~/.config/hypr/scripts/notif-center-toggle.sh ;;
    "Open Settings Hub") ~/.config/hypr/scripts/settings-hub.sh ;;
    "Open Control Center") ~/.config/hypr/scripts/control-center.sh ;;
    "Monitor Control") ~/.config/hypr/scripts/monitor-control.sh menu ;;
    "Run Dev Health") kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/dev-health.sh; read -r -p 'Press enter to close'" ;;
    "Run Dev Health (JSON)") kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/dev-health.sh --json; read -r -p 'Press enter to close'" ;;
    "Project Resume") ~/.config/hypr/scripts/project-resume.sh ;;
    "Recover Desktop") ~/.config/hypr/scripts/desktop-recovery.sh menu ;;
    "Project Profiles") kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/project-profile.sh status; read -r -p 'Press enter to close'" ;;
    *)
      return 1
      ;;
  esac
}
