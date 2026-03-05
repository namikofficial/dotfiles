#!/usr/bin/env sh
set -eu

action="${1:-}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Widgets "$1" "${2:-}"
}

run_bg() {
  "$@" >/dev/null 2>&1 &
}

open_terminal_cmd() {
  cmd="${1:-}"
  [ -n "$cmd" ] || return 1

  if command -v kitty >/dev/null 2>&1; then
    run_bg kitty sh -lc "$cmd"
    return 0
  fi
  if command -v foot >/dev/null 2>&1; then
    run_bg foot -e sh -lc "$cmd"
    return 0
  fi
  if command -v alacritty >/dev/null 2>&1; then
    run_bg alacritty -e sh -lc "$cmd"
    return 0
  fi
  if command -v wezterm >/dev/null 2>&1; then
    run_bg wezterm start -- sh -lc "$cmd"
    return 0
  fi

  return 1
}

case "$action" in
  weather)
    if command -v xdg-open >/dev/null 2>&1; then
      run_bg xdg-open "https://wttr.in"
    else
      notify "Weather action unavailable" "xdg-open is missing."
    fi
    ;;
  music)
    if command -v playerctl >/dev/null 2>&1; then
      playerctl play-pause >/dev/null 2>&1 || true
    else
      notify "Music control unavailable" "playerctl is missing."
    fi
    ;;
  network | vpn)
    if command -v nm-connection-editor >/dev/null 2>&1; then
      run_bg nm-connection-editor
    elif command -v nmtui >/dev/null 2>&1; then
      open_terminal_cmd "nmtui" || notify "Network action unavailable" "No terminal found."
    else
      notify "Network action unavailable" "Install networkmanager tools."
    fi
    ;;
  power | quick-actions)
    run_bg "$HOME/.config/hypr/scripts/quick-actions.sh"
    ;;
  ram)
    if command -v btop >/dev/null 2>&1; then
      open_terminal_cmd "btop" || notify "RAM action unavailable" "No terminal found."
    elif command -v htop >/dev/null 2>&1; then
      open_terminal_cmd "htop" || notify "RAM action unavailable" "No terminal found."
    else
      notify "RAM action unavailable" "Install btop or htop."
    fi
    ;;
  gpu)
    if command -v nvtop >/dev/null 2>&1; then
      open_terminal_cmd "nvtop" || notify "GPU action unavailable" "No terminal found."
    elif command -v btop >/dev/null 2>&1; then
      open_terminal_cmd "btop" || notify "GPU action unavailable" "No terminal found."
    else
      notify "GPU action unavailable" "Install nvtop or btop."
    fi
    ;;
  disk)
    if command -v baobab >/dev/null 2>&1; then
      run_bg baobab
    elif command -v dolphin >/dev/null 2>&1; then
      run_bg dolphin /
    elif command -v xdg-open >/dev/null 2>&1; then
      run_bg xdg-open /
    else
      notify "Disk action unavailable" "No file manager found."
    fi
    ;;
  volume)
    if command -v pavucontrol >/dev/null 2>&1; then
      run_bg pavucontrol
    else
      run_bg "$HOME/.config/hypr/scripts/volume-control.sh" mute
    fi
    ;;
  brightness)
    run_bg "$HOME/.config/hypr/scripts/brightness-control.sh" up
    ;;
  logs)
    run_bg "$HOME/.config/hypr/scripts/logs-workspace.sh" open
    ;;
  screenshot)
    run_bg "$HOME/.config/hypr/scripts/screenshot.sh" area
    ;;
  notes)
    run_bg "$HOME/.config/hypr/scripts/open-notes.sh"
    ;;
  apps)
    run_bg "$HOME/.config/hypr/scripts/launcher.sh"
    ;;
  lock)
    run_bg "$HOME/.config/hypr/scripts/lock.sh"
    ;;
  workspace)
    run_bg "$HOME/.config/hypr/scripts/workspace-overview-toggle.sh"
    ;;
  *)
    notify "Unknown widget action" "$action"
    exit 1
    ;;
esac
