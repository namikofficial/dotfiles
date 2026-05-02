#!/usr/bin/env bash
set -euo pipefail

workspace_for() {
  echo scratch_spatial
}

runtime_dir() {
  local candidate
  for candidate in \
    "${XDG_RUNTIME_DIR:-}/noxflow" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/noxflow" \
    "/tmp/noxflow-${UID:-$(id -u)}"; do
    [ -n "$candidate" ] || continue
    mkdir -p "$candidate" 2>/dev/null || continue
    [ -w "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  printf '/tmp\n'
}

state_dir="$(runtime_dir)"

dashboard_script="$HOME/.config/hypr/scripts/scratchpad-dashboard.py"
dashboard_pidfile="$state_dir/scratchpad-dashboard.pid"
scratch_state="$state_dir/scratchpad-state.json"
dashboard_log="$state_dir/scratchpad-dashboard.log"

spatial_visible() {
  hyprctl -j monitors 2>/dev/null | jq -e '
    .[] | select((.specialWorkspace.name // "") | contains("scratch_spatial"))
  ' >/dev/null 2>&1
}

toggle_workspace() {
  hyprctl dispatch togglespecialworkspace scratch_spatial >/dev/null 2>&1 || true
}

show_workspace() {
  spatial_visible || toggle_workspace
}

window_exists() {
  local class_name="$1"
  hyprctl clients 2>/dev/null | grep -q "class: ${class_name}"
}

update_state() {
  local name="$1" status="$2"
  python3 - "$scratch_state" "$name" "$status" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
name = sys.argv[2]
status = sys.argv[3]
data = {}
if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception:
        data = {}
data[name] = status
path.write_text(json.dumps(data, indent=2))
PY
}

show_dashboard() {
  if [ -f "$dashboard_pidfile" ]; then
    pid="$(cat "$dashboard_pidfile" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      hyprctl dispatch focuswindow "title:Spatial Scratchpad" >/dev/null 2>&1 || true
      return 0
    fi
    rm -f "$dashboard_pidfile"
  fi
  [ -x "$dashboard_script" ] || return 0
  NOXFLOW_SCRATCH_RUNTIME="$state_dir" "$dashboard_script" >>"$dashboard_log" 2>&1 &
  return 0
}

spawn_terminal() {
  kitty --class noxflow-scratch-terminal --title "Terminal" -e zsh -lic '
    if ! command -v tmux >/dev/null 2>&1; then exec zsh -l; fi
    tmux -L scratch set-option -g default-shell "$SHELL" >/dev/null 2>&1 || true
    exec tmux -L scratch new-session -A -s scratch-terminal "zsh -l"
  '
}

spawn_music() {
  if command -v ncspot >/dev/null 2>&1; then
    kitty --class noxflow-scratch-music --title "Music" -e ncspot
  else
    kitty --class noxflow-scratch-music --title "Music" -e bash -lc 'command -v cmus >/dev/null 2>&1 && exec cmus || exec bash'
  fi
}

spawn_notes() {
  kitty --class noxflow-scratch-notes --title "Notes" -e bash -lc '
    cd "$HOME/Documents/notes" 2>/dev/null || cd "$HOME"
    if command -v hx >/dev/null 2>&1; then exec hx; fi
    if command -v micro >/dev/null 2>&1; then exec micro; fi
    exec nano
  '
}

spawn_obsidian() {
  if hyprctl clients 2>/dev/null | grep -qi "class: .*obsidian"; then
    hyprctl dispatch focuswindow "class:^(obsidian|Obsidian)$" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v obsidian >/dev/null 2>&1; then
    obsidian "$HOME/Documents/notes/namikBrain" >/dev/null 2>&1 &
    return 0
  fi
  spawn_notes
}

spawn_db() {
  kitty --class noxflow-scratch-db --title "Database" -e zsh -lic '
    if [ -n "${DATABASE_URL:-}" ]; then
      if command -v pgcli >/dev/null 2>&1; then pgcli "$DATABASE_URL" || true; fi
      if command -v psql >/dev/null 2>&1; then psql "$DATABASE_URL" || true; fi
    fi
    if command -v lazydocker >/dev/null 2>&1; then exec lazydocker; fi
    printf "Database scratchpad\n\n"
    printf "No DATABASE_URL is exported, so I did not open psql and trigger a password prompt.\n"
    printf "Export DATABASE_URL or start your DB stack, then run pgcli/psql here.\n\n"
    exec zsh -l
  '
}

spawn_browser_devtools() {
  if command -v google-chrome-stable >/dev/null 2>&1; then
    google-chrome-stable --class=noxflow-scratch-browser --new-window --auto-open-devtools-for-tabs about:blank >/dev/null 2>&1 &
    return 0
  fi
  if command -v chromium >/dev/null 2>&1; then
    chromium --class=noxflow-scratch-browser --new-window --auto-open-devtools-for-tabs about:blank >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

spawn_ai() {
  kitty --class noxflow-scratch-ai --title "AI" -e zsh -lic '
    cd "$HOME/Documents/code" 2>/dev/null || cd "$HOME"
    if command -v codex >/dev/null 2>&1; then exec codex; fi
    llm-manager status || true
    echo
    llm-manager logs || true
    exec zsh -l
  '
}

spawn_logs() {
  kitty --class noxflow-scratch-logs --title "Logs" -e zsh -lic 'journalctl -f --no-hostname --no-pager || exec zsh -l'
}

ensure_spawned() {
  case "$1" in
    terminal)
      window_exists noxflow-scratch-terminal || spawn_terminal >/dev/null 2>&1 &
      show_workspace
      update_state terminal active
      ;;
    music)
      window_exists noxflow-scratch-music || spawn_music >/dev/null 2>&1 &
      show_workspace
      update_state music active
      ;;
    notes)
      window_exists noxflow-scratch-notes || spawn_notes >/dev/null 2>&1 &
      show_workspace
      update_state notes active
      ;;
    obsidian)
      spawn_obsidian
      update_state obsidian active
      ;;
    db)
      window_exists noxflow-scratch-db || spawn_db >/dev/null 2>&1 &
      show_workspace
      update_state db active
      ;;
    browser-devtools)
      spawn_browser_devtools || true
      show_workspace
      update_state browser-devtools active
      ;;
    ai)
      window_exists noxflow-scratch-ai || spawn_ai >/dev/null 2>&1 &
      show_workspace
      update_state ai active
      ;;
    logs)
      window_exists noxflow-scratch-logs || spawn_logs >/dev/null 2>&1 &
      show_workspace
      update_state logs active
      ;;
    scene)
      window_exists noxflow-scratch-ai || spawn_ai >/dev/null 2>&1 &
      window_exists noxflow-scratch-logs || spawn_logs >/dev/null 2>&1 &
      show_workspace
      update_state ai active
      update_state logs active
      ;;
    *)
      exit 1
      ;;
  esac
}

case "${1:-menu}" in
  menu)
    show_dashboard
    exit 0
    ;;
  launch)
    ensure_spawned "${2:-terminal}"
    ;;
  toggle)
    case "${2:-scene}" in
      scene)
        if spatial_visible; then
          toggle_workspace
        else
          ensure_spawned scene
        fi
        ;;
      terminal)
        window_exists noxflow-scratch-terminal || spawn_terminal >/dev/null 2>&1 &
        sleep 0.15
        toggle_workspace
        update_state terminal active
        ;;
      *) ensure_spawned "${2:-scene}" ;;
    esac
    ;;
  *)
    ensure_spawned "$1"
    ;;
esac
