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
  local id
  id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf '1')"
  case "$id" in
    ''|*[!0-9-]*) id=1 ;;
  esac
  if [ "$id" -gt 0 ]; then
    printf '%s\n' "$id"
    return 0
  fi
  focused_monitor_json | jq -r '.activeWorkspace.id // 1' 2>/dev/null || printf '1\n'
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
mx = int(monitor.get("x", 0))
my = int(monitor.get("y", 0))
mw = int(monitor.get("width", 1600))
mh = int(monitor.get("height", 900))
reserved = list(monitor.get("reserved", [0, 0, 0, 0]) or [0, 0, 0, 0])
reserved += [0] * (4 - len(reserved))
left, top, right, bottom = [int(v or 0) for v in reserved[:4]]
layout = registry.get("layout", {})
margin = int(layout.get("margin", 10))
usable_x = mx + left + margin
usable_y = my + top + margin
usable_w = max(320, mw - left - right - (margin * 2))
usable_h = max(240, mh - top - bottom - (margin * 2))

def pct(name, default):
    return int(geom.get(name, default))

min_w = min(int(geom.get("min_w", 320)), usable_w)
min_h = min(int(geom.get("min_h", 180)), usable_h)
w = min(usable_w, max(min_w, round(usable_w * pct("w", 50) / 100)))
h = min(usable_h, max(min_h, round(usable_h * pct("h", 50) / 100)))
x = usable_x + round(usable_w * pct("x", 0) / 100)
y = usable_y + round(usable_h * pct("y", 0) / 100)
x = min(max(usable_x, x), usable_x + usable_w - w)
y = min(max(usable_y, y), usable_y + usable_h - h)
print(x, y, w, h)
PY
}

apply_geometry() {
  local address="$1" pad="$2" kind="$3"
  [ -n "$address" ] || return 0
  read -r x y w h < <(geometry_px "$pad" "$kind")
  hyprctl --batch "dispatch setfloating address:$address; dispatch resizewindowpixel exact $w $h,address:$address; dispatch movewindowpixel exact $x $y,address:$address" >/dev/null 2>&1 || true
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
      kill "$pid" >/dev/null 2>&1 || true
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

spawn_pad_process() {
  case "$1" in
    terminal) spawn_terminal >/dev/null 2>&1 & ;;
    music) spawn_music >/dev/null 2>&1 & ;;
    notes) spawn_notes >/dev/null 2>&1 & ;;
    db) spawn_db >/dev/null 2>&1 & ;;
    browser-devtools) spawn_browser_devtools >/dev/null 2>&1 || true ;;
    ai) spawn_ai >/dev/null 2>&1 & ;;
    logs) spawn_logs >/dev/null 2>&1 & ;;
    *) return 1 ;;
  esac
}

wait_for_client() {
  local class_name="$1" address
  for _ in {1..24}; do
    address="$(client_address "$class_name" || true)"
    if [ -n "$address" ]; then
      printf '%s\n' "$address"
      return 0
    fi
    sleep 0.05
  done
  return 1
}

normal_workspace_window_json() {
  local workspace="$1"
  hyprctl -j clients 2>/dev/null | jq -c --argjson workspace "$workspace" '
    [
      .[]
      | select((.workspace.id // 0) == $workspace)
      | select(((.class // "") | test("^noxflow-scratch"; "i") | not))
      | select((.title // "") != "Spatial Scratchpad")
    ]
    | sort_by(.focusHistoryID // 999999)
    | .[0] // {}
  ' 2>/dev/null || printf '{}\n'
}

launch_overlay_pad() {
  local pad="$1" class_name address
  class_name="$(pad_class "$pad")"
  [ -n "$class_name" ] || return 1
  window_exists "$class_name" || spawn_pad_process "$pad"
  address="$(wait_for_client "$class_name" || true)"
  [ -n "$address" ] || return 0
  hyprctl dispatch movetoworkspacesilent "special:$(workspace_for),address:$address" >/dev/null 2>&1 || true
  arrange_overlay
  show_workspace
  hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1 || true
  update_state "$pad" active
}

arrange_overlay() {
  local pad class_name address
  for pad in terminal notes db ai logs music browser-devtools; do
    class_name="$(pad_class "$pad")"
    [ -n "$class_name" ] || continue
    address="$(client_address "$class_name" || true)"
    [ -n "$address" ] || continue
    hyprctl dispatch movetoworkspacesilent "special:$(workspace_for),address:$address" >/dev/null 2>&1 || true
    apply_geometry "$address" "$pad" overlay_geometry
  done
}

scene_save_state() {
  local workspace="$1"
  local active normal
  active="$(active_window_json)"
  normal="$(normal_workspace_window_json "$workspace")"
  python3 - "$scene_state" "$workspace" "$active" "$normal" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
workspace = int(sys.argv[2])
try:
    active = json.loads(sys.argv[3])
except Exception:
    active = {}
try:
    normal = json.loads(sys.argv[4])
except Exception:
    normal = {}

def is_scratch(client):
    cls = str(client.get("class", ""))
    title = str(client.get("title", ""))
    return cls.lower().startswith("noxflow-scratch") or title == "Spatial Scratchpad"

target = active
if is_scratch(active) or int(active.get("workspace", {}).get("id", 0) or 0) != workspace:
    target = normal if normal.get("address") else active

state = {
    "workspace": workspace,
    "main": {
        "address": target.get("address", ""),
        "class": target.get("class", ""),
        "title": target.get("title", ""),
        "floating": bool(target.get("floating", False)),
        "fullscreen": int(target.get("fullscreen", 0) or 0),
        "at": target.get("at", []),
        "size": target.get("size", []),
    }
}
path.write_text(json.dumps(state, indent=2))
PY
}

scene_main_address() {
  [ -s "$scene_state" ] || return 1
  jq -r '.main.address // empty' "$scene_state" 2>/dev/null
}

scene_state_live() {
  local main
  main="$(scene_main_address || true)"
  [ -n "$main" ] || return 1
  hyprctl -j clients 2>/dev/null | jq -e --arg address "$main" '
    any(.[]; (.address // "") == $address)
  ' >/dev/null 2>&1
}

scene_enter() {
  local workspace
  workspace="$(active_workspace_id)"
  scene_save_state "$workspace"
  spatial_visible && toggle_workspace

  window_exists "$(pad_class ai)" || spawn_pad_process ai
  window_exists "$(pad_class logs)" || spawn_pad_process logs

  local main ai logs
  main="$(scene_main_address || true)"
  ai="$(wait_for_client "$(pad_class ai)" || true)"
  logs="$(wait_for_client "$(pad_class logs)" || true)"

  [ -n "$ai" ] && hyprctl dispatch movetoworkspacesilent "$workspace,address:$ai" >/dev/null 2>&1 || true
  [ -n "$logs" ] && hyprctl dispatch movetoworkspacesilent "$workspace,address:$logs" >/dev/null 2>&1 || true
  sleep 0.05

  [ -n "$main" ] && hyprctl dispatch focuswindow "address:$main" >/dev/null 2>&1 || true
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
    hyprctl dispatch focuswindow "address:$main" >/dev/null 2>&1 || true
    hyprctl --batch "dispatch movewindowpixel exact $x $y,address:$main; dispatch resizewindowpixel exact $w $h,address:$main" >/dev/null 2>&1 || true
    [ "$floating" = "false" ] && hyprctl dispatch settiled "address:$main" >/dev/null 2>&1 || true
    hyprctl dispatch focuswindow "address:$main" >/dev/null 2>&1 || true
  fi

  local ai logs
  ai="$(client_address "$(pad_class ai)" || true)"
  logs="$(client_address "$(pad_class logs)" || true)"
  [ -n "$ai" ] && hyprctl dispatch movetoworkspacesilent "special:scratch_spatial,address:$ai" >/dev/null 2>&1 || true
  [ -n "$logs" ] && hyprctl dispatch movetoworkspacesilent "special:scratch_spatial,address:$logs" >/dev/null 2>&1 || true
  arrange_overlay
  rm -f "$scene_state"
  update_state scene idle
}

scene_toggle() {
  if [ -s "$scene_state" ] && scene_state_live; then
    scene_exit
  else
    rm -f "$scene_state"
    scene_enter
  fi
}

ensure_spawned() {
  case "$1" in
    terminal)
      launch_overlay_pad terminal
      ;;
    music)
      launch_overlay_pad music
      ;;
    notes)
      launch_overlay_pad notes
      ;;
    obsidian)
      spawn_obsidian
      update_state obsidian active
      ;;
    db)
      launch_overlay_pad db
      ;;
    browser-devtools)
      launch_overlay_pad browser-devtools
      ;;
    ai)
      launch_overlay_pad ai
      ;;
    logs)
      launch_overlay_pad logs
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
        if spatial_visible; then
          toggle_workspace
        else
          launch_overlay_pad terminal
        fi
        ;;
      *) ensure_spawned "${2:-scene}" ;;
    esac
    ;;
  *)
    ensure_spawned "$1"
    ;;
esac
