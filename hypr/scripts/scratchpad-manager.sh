#!/usr/bin/env bash
set -euo pipefail

spawn_terminal() {
  kitty --class noxflow-scratch-terminal --title "Scratch Terminal" -e tmux new-session -A -s scratch-terminal
}

spawn_music() {
  kitty --class noxflow-scratch-music --title "Scratch Music" -e bash -lc 'command -v ncmpcpp >/dev/null 2>&1 && exec ncmpcpp || exec bash'
}

spawn_notes() {
  "$HOME/.config/hypr/scripts/open-notes.sh"
}

spawn_db() {
  kitty --class noxflow-scratch-db --title "Scratch DB" -e bash -lc 'exec psql "${DATABASE_URL:-postgresql://localhost/postgres}"'
}

spawn_browser_devtools() {
  if command -v google-chrome-stable >/dev/null 2>&1; then
    google-chrome-stable --new-window --auto-open-devtools-for-tabs about:blank >/dev/null 2>&1 &
    return 0
  fi
  if command -v chromium >/dev/null 2>&1; then
    chromium --new-window --auto-open-devtools-for-tabs about:blank >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

spawn_ai() {
  kitty --class noxflow-scratch-ai --title "Scratch AI" -e bash -lc 'llm-manager status; echo; llm-manager logs'
}

spawn_logs() {
  "$HOME/.config/hypr/scripts/logs-workspace.sh" stack
}

toggle_special() {
  hyprctl dispatch togglespecialworkspace "$1" >/dev/null 2>&1 || true
}

ensure_spawned() {
  case "$1" in
    terminal)
      pgrep -af 'noxflow-scratch-terminal' >/dev/null 2>&1 || spawn_terminal >/dev/null 2>&1 &
      toggle_special scratch_terminal
      ;;
    music)
      pgrep -af 'noxflow-scratch-music' >/dev/null 2>&1 || spawn_music >/dev/null 2>&1 &
      toggle_special scratch_music
      ;;
    notes)
      spawn_notes
      ;;
    db)
      pgrep -af 'noxflow-scratch-db' >/dev/null 2>&1 || spawn_db >/dev/null 2>&1 &
      toggle_special scratch_db
      ;;
    browser-devtools)
      spawn_browser_devtools || true
      ;;
    ai)
      pgrep -af 'noxflow-scratch-ai' >/dev/null 2>&1 || spawn_ai >/dev/null 2>&1 &
      toggle_special scratch_ai
      ;;
    logs)
      spawn_logs
      ;;
    *)
      exit 1
      ;;
  esac
}

case "${1:-menu}" in
  menu)
    choice="$(
      printf '%s\n' terminal music notes db browser-devtools ai logs | rofi -dmenu -i \
        -p 'Scratchpads' \
        -theme "$HOME/.config/rofi/actions.rasi" \
        -mesg 'Named scratchpads: terminal, music, notes, db, browser-devtools, ai, logs.'
    )"
    [ -n "$choice" ] || exit 0
    exec "$0" "$choice"
    ;;
  *)
    ensure_spawned "$1"
    ;;
esac
