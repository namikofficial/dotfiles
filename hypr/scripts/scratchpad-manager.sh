#!/usr/bin/env bash
set -euo pipefail

workspace_for() {
  echo scratch_spatial
}

runtime_dir() {
  local candidate
  for candidate in \
    "${NOXFLOW_SCRATCH_RUNTIME:-}" \
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
registry_file="$HOME/.config/hypr/scripts/scratchpad-registry.toml"
dashboard_pidfile="$state_dir/scratchpad-dashboard.pid"
scratch_state="$state_dir/scratchpad-state.json"
scene_state="$state_dir/scratchpad-scene-state.json"
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

pad_class() {
  local pad="$1"
  python3 - "$registry_file" "$pad" <<'PY'
import sys, tomllib
from pathlib import Path
registry = tomllib.loads(Path(sys.argv[1]).read_text())
print(registry["scratchpads"].get(sys.argv[2], {}).get("class", ""))
PY
}

client_address() {
  local class_name="$1"
  hyprctl -j clients 2>/dev/null | jq -r --arg c "$class_name" '
    .[] | select((.class // "" | ascii_downcase) == ($c | ascii_downcase)) | .address
  ' | head -n1
}

active_window_json() {
  hyprctl -j activewindow 2>/dev/null || printf '{}\n'
}

focused_monitor_json() {
  hyprctl -j monitors 2>/dev/null | jq -c '
    (map(select(.focused == true))[0] // .[0] // {})
  '
}

active_workspace_id() {
  hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf '1\n'
}

geometry_px() {
  local pad="$1" kind="$2"
  python3 - "$registry_file" "$pad" "$kind" "$(focused_monitor_json)" <<'PY'
import json, sys, tomllib
from pathlib import Path

registry = tomllib.loads(Path(sys.argv[1]).read_text())
pad_name = sys.argv[2]
if pad_name == "main":
    pad = {"scene_geometry": registry.get("scene", {}).get("main", {}).get("geometry", {})}
else:
    pad = registry["scratchpads"][pad_name]
kind = sys.argv[3]
monitor = json.loads(sys.argv[4] or "{}")
geom = pad.get(kind, {})
mw = int(monitor.get("width", 1600))
mh = int(monitor.get("height", 900))
mx = int(monitor.get("x", 0))
my = int(monitor.get("y", 0))
x = mx + round(mw * int(geom.get("x", 0)) / 100)
y = my + round(mh * int(geom.get("y", 0)) / 100)
w = round(mw * int(geom.get("w", 50)) / 100)
h = round(mh * int(geom.get("h", 50)) / 100)
print(x, y, w, h)
PY
}

apply_geometry() {
  local address="$1" pad="$2" kind="$3"
  [ -n "$address" ] || return 0
  read -r x y w h < <(geometry_px "$pad" "$kind")
  hyprctl --batch "dispatch setfloating address:$address; dispatch movewindowpixel exact $x $y,address:$address; dispatch resizewindowpixel exact $w $h,address:$address" >/dev/null 2>&1 || true
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
    exec "$HOME/.config/hypr/scripts/local-llm-chat.sh"
  '
}

spawn_logs() {
  kitty --class noxflow-scratch-logs --title "Logs" -e zsh -lic 'journalctl -f --no-hostname --no-pager || exec zsh -l'
}

scene_save_state() {
  local active
  active="$(active_window_json)"
  python3 - "$scene_state" "$active" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    active = json.loads(sys.argv[2])
except Exception:
    active = {}
state = {
    "main": {
        "address": active.get("address", ""),
        "class": active.get("class", ""),
        "title": active.get("title", ""),
        "floating": bool(active.get("floating", False)),
        "fullscreen": int(active.get("fullscreen", 0) or 0),
        "at": active.get("at", []),
        "size": active.get("size", []),
    }
}
path.write_text(json.dumps(state, indent=2))
PY
}

scene_main_address() {
  [ -s "$scene_state" ] || return 1
  jq -r '.main.address // empty' "$scene_state" 2>/dev/null
}

scene_enter() {
  scene_save_state
  local workspace
  workspace="$(active_workspace_id)"

  window_exists "$(pad_class ai)" || spawn_ai >/dev/null 2>&1 &
  window_exists "$(pad_class logs)" || spawn_logs >/dev/null 2>&1 &
  sleep 0.35

  local main ai logs
  main="$(scene_main_address || true)"
  ai="$(client_address "$(pad_class ai)" || true)"
  logs="$(client_address "$(pad_class logs)" || true)"

  [ -n "$ai" ] && hyprctl dispatch movetoworkspacesilent "$workspace,address:$ai" >/dev/null 2>&1 || true
  [ -n "$logs" ] && hyprctl dispatch movetoworkspacesilent "$workspace,address:$logs" >/dev/null 2>&1 || true
  sleep 0.05

  apply_geometry "$main" main scene_geometry
  apply_geometry "$ai" ai scene_geometry
  apply_geometry "$logs" logs scene_geometry

  [ -n "$main" ] && hyprctl dispatch focuswindow "address:$main" >/dev/null 2>&1 || true
  update_state scene active
  update_state ai active
  update_state logs active
}

scene_exit() {
  local main x y w h floating
  main="$(scene_main_address || true)"
  if [ -n "$main" ] && [ -s "$scene_state" ]; then
    read -r x y w h floating < <(python3 - "$scene_state" <<'PY'
import json, sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text())
main = state.get("main", {})
at = main.get("at", [0, 0])
size = main.get("size", [1000, 700])
print(at[0] if len(at) > 0 else 0, at[1] if len(at) > 1 else 0,
      size[0] if len(size) > 0 else 1000, size[1] if len(size) > 1 else 700,
      "true" if main.get("floating") else "false")
PY
)
    hyprctl --batch "dispatch movewindowpixel exact $x $y,address:$main; dispatch resizewindowpixel exact $w $h,address:$main" >/dev/null 2>&1 || true
    [ "$floating" = "false" ] && hyprctl dispatch settiled "address:$main" >/dev/null 2>&1 || true
    hyprctl dispatch focuswindow "address:$main" >/dev/null 2>&1 || true
  fi

  local ai logs
  ai="$(client_address "$(pad_class ai)" || true)"
  logs="$(client_address "$(pad_class logs)" || true)"
  [ -n "$ai" ] && hyprctl dispatch movetoworkspacesilent "special:scratch_spatial,address:$ai" >/dev/null 2>&1 || true
  [ -n "$logs" ] && hyprctl dispatch movetoworkspacesilent "special:scratch_spatial,address:$logs" >/dev/null 2>&1 || true
  rm -f "$scene_state"
  update_state scene idle
}

scene_toggle() {
  if [ -s "$scene_state" ]; then
    scene_exit
  else
    scene_enter
  fi
}

ensure_spawned() {
  case "$1" in
    terminal)
      window_exists "$(pad_class terminal)" || spawn_terminal >/dev/null 2>&1 &
      show_workspace
      update_state terminal active
      ;;
    music)
      window_exists "$(pad_class music)" || spawn_music >/dev/null 2>&1 &
      show_workspace
      update_state music active
      ;;
    notes)
      window_exists "$(pad_class notes)" || spawn_notes >/dev/null 2>&1 &
      show_workspace
      update_state notes active
      ;;
    obsidian)
      spawn_obsidian
      update_state obsidian active
      ;;
    db)
      window_exists "$(pad_class db)" || spawn_db >/dev/null 2>&1 &
      show_workspace
      update_state db active
      ;;
    browser-devtools)
      spawn_browser_devtools || true
      show_workspace
      update_state browser-devtools active
      ;;
    ai)
      scene_enter
      ;;
    logs)
      scene_enter
      ;;
    scene)
      scene_enter
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
      scene) scene_toggle ;;
      terminal)
        window_exists "$(pad_class terminal)" || spawn_terminal >/dev/null 2>&1 &
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
