#!/usr/bin/env bash
set -euo pipefail

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "System Update" "$1" "${2:-}"
}

log_file="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/system-update.log"
mkdir -p "$(dirname "$log_file")"
printf '%s system-update invoked\n' "$(date -Iseconds)" >>"$log_file"

run_update() {
  if command -v paru >/dev/null 2>&1; then
    paru -Syu
    return
  fi
  if command -v yay >/dev/null 2>&1; then
    yay -Syu
    return
  fi
  sudo pacman -Syu
}

open_in_terminal() {
  local body='set -euo pipefail; '"$(declare -f run_update)"'; run_update; read -r -p "Press enter to close"'

  if command -v kitty >/dev/null 2>&1; then
    setsid -f kitty -e sh -lc "$body" >/dev/null 2>&1 && return 0
  fi
  if command -v foot >/dev/null 2>&1; then
    setsid -f foot -e sh -lc "$body" >/dev/null 2>&1 && return 0
  fi
  if command -v alacritty >/dev/null 2>&1; then
    setsid -f alacritty -e sh -lc "$body" >/dev/null 2>&1 && return 0
  fi
  if command -v wezterm >/dev/null 2>&1; then
    setsid -f wezterm start -- sh -lc "$body" >/dev/null 2>&1 && return 0
  fi
  return 1
}

if open_in_terminal; then
  exit 0
fi

notify "No terminal launcher found" "Running update directly in background."
run_update
