#!/usr/bin/env sh
# tmux-projects.sh — open tmux-sessionizer (FZF project picker) in a float
# Historical helper; the primary work scene now uses Super + Shift + grave.
set -eu

class_name="noxflow-tmux-projects"
sessionizer="${HOME}/.local/bin/tmux-sessionizer"

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

focus_window() {
  target_lua="$(lua_string "$1")"
  hyprctl eval "hl.dispatch(hl.dsp.focus({ window = ${target_lua} }))" >/dev/null
}

# If an instance is already visible, focus it instead of spawning a new one
if hyprctl clients 2>/dev/null | rg -q "class: ${class_name}"; then
  focus_window "class:${class_name}" >/dev/null 2>&1 || true
  exit 0
fi

if [ ! -x "$sessionizer" ]; then
  notify-send -a "tmux-projects" "tmux-sessionizer not found" \
    "Run: git submodule update --init private/scripts" 2>/dev/null || true
  exit 1
fi

kitty --class "$class_name" --title "tmux · projects" \
  -e "$sessionizer" >/dev/null 2>&1 &
