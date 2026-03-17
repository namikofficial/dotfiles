#!/usr/bin/env sh
# tmux-scratch.sh — quake-style drop-down tmux terminal
# Bound to: Super + grave  (the ` key)
#
# How it works:
#   A windowrule in hyprland.conf catches any kitty window with class
#   "noxflow-tmux-scratch" and silently places it in special:scratch_tmux.
#   We just spawn the window once (it hides itself immediately) then
#   use togglespecialworkspace to drop it down / send it back up.
set -eu

special_ws="scratch_tmux"
class_name="noxflow-tmux-scratch"

window_exists() {
  hyprctl clients 2>/dev/null | grep -q "class: ${class_name}"
}

case "${1:-toggle}" in
  toggle)
    if ! window_exists; then
      # Spawn the window — the windowrule sends it to special:scratch_tmux
      # silently so it doesn't steal focus.  Give Hyprland a moment to apply
      # the rule before we toggle so the first open feels instant.
      kitty --class "$class_name" --title "tmux · scratch" \
        --override background_opacity=0.88 \
        -e tmux new-session -A -s scratch >/dev/null 2>&1 &
      sleep 0.20
    fi
    hyprctl dispatch togglespecialworkspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  send)
    hyprctl dispatch movetoworkspacesilent "special:${special_ws}" >/dev/null 2>&1 || true
    hyprctl dispatch togglespecialworkspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  stash)
    hyprctl dispatch movetoworkspacesilent "special:${special_ws}" >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: $0 [toggle|send|stash]" >&2
    exit 1
    ;;
esac
