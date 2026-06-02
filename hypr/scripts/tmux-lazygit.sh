#!/usr/bin/env bash
# tmux-lazygit.sh — open lazygit in a float, rooted at the focused window's git repo
# Bound to: Super + Ctrl + grave  (the ` key)
set -euo pipefail

class_name="noxflow-lazygit"

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

focus_window() {
  local target_lua
  target_lua="$(lua_string "$1")"
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = ${target_lua} }))" >/dev/null
}

if ! command -v lazygit >/dev/null 2>&1; then
  notify-send -a "tmux-lazygit" "lazygit not found" \
    "Install with: sudo pacman -S lazygit" 2>/dev/null || true
  exit 1
fi

# If an instance is already visible, focus it
if hyprctl clients 2>/dev/null | rg -q "class: ${class_name}"; then
  focus_window "class:${class_name}" >/dev/null 2>&1 || true
  exit 0
fi

# Detect the working directory of the currently focused window
cwd=""
if command -v jq >/dev/null 2>&1; then
  focused_pid="$(hyprctl -j activewindow 2>/dev/null | jq -r '.pid // empty')"
  if [ -n "$focused_pid" ]; then
    cwd="$(readlink "/proc/${focused_pid}/cwd" 2>/dev/null || true)"
  fi
fi
[ -d "$cwd" ] || cwd="$HOME"

# Walk up to the nearest git root (fallback to cwd itself)
git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"

kitty --class "$class_name" --title "lazygit" \
  -e lazygit -p "$git_root" >/dev/null 2>&1 &
