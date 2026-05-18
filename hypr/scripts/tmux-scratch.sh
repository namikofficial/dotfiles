#!/usr/bin/env sh
# tmux-scratch.sh — quake-style drop-down tmux terminal
# Bound to: Super + grave  (the ` key)
#
# How it works:
#   A windowrule in hyprland.lua catches any kitty window with class
#   "noxflow-tmux-scratch" and silently places it in special:scratch_tmux.
#   We just spawn the window once (it hides itself immediately) then
#   use togglespecialworkspace to drop it down / send it back up.
set -eu

special_ws="scratch_tmux"
class_name="noxflow-tmux-scratch"

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

hypr_eval() {
  hyprctl eval "$1" >/dev/null
}

toggle_special_workspace() {
  ws_lua="$(lua_string "$1")"
  hypr_eval "hl.dispatch(hl.dsp.workspace.toggle_special(${ws_lua}))"
}

move_active_to_workspace() {
  ws_lua="$(lua_string "$1")"
  hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = ${ws_lua}, follow = false }))"
}

window_exists() {
  hyprctl clients 2>/dev/null | grep -q "class: ${class_name}"
}

case "${1:-toggle}" in
  toggle)
    if ! window_exists; then
      # Spawn the window — the windowrule sends it to special:scratch_tmux
      # silently so it doesn't steal focus.  Give Hyprland a moment to apply
      # the rule before we toggle so the first open feels instant.
      # Use a dedicated socket (-L scratch) so this server is completely
      # isolated from the main tmux server — no continuum restore, no
      # other sessions bleeding in.
      kitty --class "$class_name" --title "tmux · scratch" \
        --override background_opacity=0.88 \
        -e tmux -L scratch new-session -A -s scratch >/dev/null 2>&1 &
      sleep 0.20
    fi
    toggle_special_workspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  send)
    move_active_to_workspace "special:${special_ws}" >/dev/null 2>&1 || true
    toggle_special_workspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  stash)
    move_active_to_workspace "special:${special_ws}" >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: $0 [toggle|send|stash]" >&2
    exit 1
    ;;
esac
