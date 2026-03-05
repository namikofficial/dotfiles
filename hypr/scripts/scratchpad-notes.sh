#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
special_ws="scratch_notes"
class_name="noxflow-scratch-notes"
notes_dir="${NOXFLOW_NOTES_DIR:-$HOME/Documents/notes}"
notes_file="${NOXFLOW_NOTES_FILE:-$notes_dir/inbox.md}"

pick_editor() {
  if command -v nvim >/dev/null 2>&1; then
    echo "nvim"
    return 0
  fi
  if command -v hx >/dev/null 2>&1; then
    echo "hx"
    return 0
  fi
  if command -v micro >/dev/null 2>&1; then
    echo "micro"
    return 0
  fi
  echo "nano"
}

launch_notes() {
  if hyprctl clients 2>/dev/null | rg -q "class: ${class_name}"; then
    return 0
  fi

  mkdir -p "$notes_dir"
  [ -f "$notes_file" ] || touch "$notes_file"
  editor_cmd="$(pick_editor)"
  kitty --class "$class_name" --title "Scratch Notes" -e sh -lc "exec ${editor_cmd} \"${notes_file}\"" >/dev/null 2>&1 &
  sleep 0.12
}

case "$mode" in
  toggle)
    launch_notes
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
