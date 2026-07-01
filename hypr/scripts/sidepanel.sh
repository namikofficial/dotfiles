#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
side_ws="sidepanel"
side_class="noxflow-sidepanel"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/noxflow"
state_file="$state_dir/sidecar-state.json"
mkdir -p "$state_dir" 2>/dev/null || true

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

current_workspace() {
  hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf '1\n'
}

normal_current_workspace() {
  local workspace
  workspace="$(current_workspace)"
  case "$workspace" in
    ''|*[!0-9-]*|0|-*) printf '1\n' ;;
    *) printf '%s\n' "$workspace" ;;
  esac
}

active_window_json() {
  hyprctl -j activewindow 2>/dev/null || printf '{}\n'
}

sidepanel_visible() {
  hyprctl -j monitors 2>/dev/null | jq -e --arg ws "special:${side_ws}" '
    .[] | (.specialWorkspace.name // "") == $ws
  ' >/dev/null 2>&1
}

sidepanel_client() {
  hyprctl -j clients 2>/dev/null | jq -r --arg ws "special:${side_ws}" --arg class "$side_class" '
    .[]
    | select((.workspace.name // "") == $ws or (.class // "") == $class)
    | .address
  ' | head -n1
}

sidepanel_clients() {
  hyprctl -j clients 2>/dev/null | jq -r --arg ws "special:${side_ws}" --arg class "$side_class" '
    .[]
    | select((.workspace.name // "") == $ws or (.class // "") == $class)
    | .address
  '
}

move_window_to_workspace() {
  address="$1"
  workspace="$2"
  [ -n "$address" ] || return 0
  address_lua="$(lua_string "address:$address")"
  ws_lua="$(lua_string "$workspace")"
  hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = ${ws_lua}, follow = false, window = ${address_lua} }))"
}

sidepanel_geometry() {
  python3 - "$(hyprctl -j monitors 2>/dev/null || printf '[]')" <<'PY' 2>/dev/null || printf '1000 60 560 820\n'
import json
import sys

try:
    monitors = json.loads(sys.argv[1])
except Exception:
    monitors = []

m = next((item for item in monitors if item.get("focused")), monitors[0] if monitors else {})
reserved = list(m.get("reserved") or [0, 0, 0, 0])
reserved += [0] * (4 - len(reserved))
left, top, right, bottom = [int(value or 0) for value in reserved[:4]]
mx = int(m.get("x", 0) or 0)
my = int(m.get("y", 0) or 0)
mw = int(m.get("width", 1600) or 1600)
mh = int(m.get("height", 900) or 900)

usable_x = mx + left
usable_y = my + top
usable_w = max(320, mw - left - right)
usable_h = max(240, mh - top - bottom)
gap = max(8, min(18, round(usable_w * 0.008)))

if usable_w < 760:
    # Very small screens: use most of the width but keep a clear margin.
    w = max(300, round(usable_w * 0.92))
elif usable_w < 1200:
    # Tablet / narrow laptop layouts: side shelf is wider for usability.
    w = max(360, min(round(usable_w * 0.48), 520))
else:
    # Desktop / normal laptop layouts: stable right-side shelf.
    w = max(460, min(round(usable_w * 0.34), 720))

h = max(360, min(round(usable_h * 0.92), usable_h - (gap * 2)))
x = usable_x + usable_w - w - gap
y = usable_y + max(gap, round((usable_h - h) / 2))

print(int(x), int(y), int(w), int(h))
PY
}

sidepanel_layouts() {
  python3 - "$(hyprctl -j monitors 2>/dev/null || printf '[]')" "$(hyprctl -j clients 2>/dev/null || printf '[]')" "$side_ws" "$side_class" <<'PY' 2>/dev/null
import json
import math
import sys

try:
    monitors = json.loads(sys.argv[1])
except Exception:
    monitors = []
try:
    clients = json.loads(sys.argv[2])
except Exception:
    clients = []
side_ws = "special:" + sys.argv[3]
side_class = sys.argv[4]

m = next((item for item in monitors if item.get("focused")), monitors[0] if monitors else {})
reserved = list(m.get("reserved") or [0, 0, 0, 0])
reserved += [0] * (4 - len(reserved))
left, top, right, bottom = [int(value or 0) for value in reserved[:4]]
mx = int(m.get("x", 0) or 0)
my = int(m.get("y", 0) or 0)
mw = int(m.get("width", 1600) or 1600)
mh = int(m.get("height", 900) or 900)

usable_x = mx + left
usable_y = my + top
usable_w = max(320, mw - left - right)
usable_h = max(240, mh - top - bottom)
gap = max(8, min(18, round(usable_w * 0.008)))

if usable_w < 760:
    shelf_w = max(300, round(usable_w * 0.92))
elif usable_w < 1200:
    shelf_w = max(360, min(round(usable_w * 0.48), 520))
else:
    shelf_w = max(460, min(round(usable_w * 0.34), 720))

shelf_h = max(360, min(round(usable_h * 0.92), usable_h - (gap * 2)))
shelf_x = usable_x + usable_w - shelf_w - gap
shelf_y = usable_y + max(gap, round((usable_h - shelf_h) / 2))

side_clients = [
    client for client in clients
    if client.get("workspace", {}).get("name") == side_ws or client.get("class") == side_class
]
side_clients.sort(key=lambda client: int(client.get("focusHistoryID", 999999) or 999999))
count = len(side_clients)
if count == 0:
    raise SystemExit(0)

if count == 1:
    layout = [(shelf_x, shelf_y, shelf_w, shelf_h)]
elif count == 2:
    h1 = (shelf_h - gap) // 2
    h2 = shelf_h - gap - h1
    layout = [
        (shelf_x, shelf_y, shelf_w, h1),
        (shelf_x, shelf_y + h1 + gap, shelf_w, h2),
    ]
else:
    cols = 2 if shelf_w >= 520 else 1
    rows = math.ceil(count / cols)
    cell_w = (shelf_w - gap * (cols - 1)) // cols
    cell_h = max(220, (shelf_h - gap * (rows - 1)) // rows)
    if cell_h * rows + gap * (rows - 1) > shelf_h:
        cell_h = max(160, (shelf_h - gap * (rows - 1)) // rows)
    layout = []
    for index in range(count):
        row = index // cols
        col = index % cols
        x = shelf_x + col * (cell_w + gap)
        y = shelf_y + row * (cell_h + gap)
        w = cell_w if col < cols - 1 else shelf_x + shelf_w - x
        h = cell_h if row < rows - 1 else shelf_y + shelf_h - y
        layout.append((x, y, w, h))

for client, (x, y, w, h) in zip(side_clients, layout):
    address = client.get("address", "")
    if address:
        print(address, int(x), int(y), int(w), int(h))
PY
}

set_sidepanel_geometry_exact() {
  address="$1"
  x="$2"
  y="$3"
  w="$4"
  h="$5"
  [ -n "$address" ] || return 0
  address_lua="$(lua_string "address:$address")"
  if ! window_is_floating "$address"; then
    hypr_eval "hl.dispatch(hl.dsp.window.float({ state = true, window = ${address_lua} }))" || return 1
  fi
  hypr_eval "hl.dispatch(hl.dsp.window.resize({ x = ${w}, y = ${h}, window = ${address_lua} }))" || return 1
  hypr_eval "hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, window = ${address_lua} }))" || return 1
}

set_sidepanel_geometry() {
  address="$1"
  geometry="$(sidepanel_geometry || true)"
  set -- $geometry
  [ "$#" -eq 4 ] || return 1
  set_sidepanel_geometry_exact "$address" "$1" "$2" "$3" "$4"
}

set_all_sidepanel_geometry() {
  sidepanel_layouts | while read -r address x y w h; do
    [ -n "$address" ] || continue
    set_sidepanel_geometry_exact "$address" "$x" "$y" "$w" "$h" || true
  done
}

focus_window() {
  address="$1"
  [ -n "$address" ] || return 0
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.focus({ window = ${address_lua} }))"
}

window_is_floating() {
  address="$1"
  [ -n "$address" ] || return 1
  hyprctl -j clients 2>/dev/null | jq -e --arg address "$address" '
    .[]
    | select((.address // "") == $address)
    | (.floating == true)
  ' >/dev/null 2>&1
}

active_window_address() {
  active_window_json | jq -r '.address // empty' 2>/dev/null || true
}

active_window_is_sidecar() {
  active_window_json | jq -e --arg ws "special:${side_ws}" '
    ((.workspace.name // "") == $ws)
    and ((.class // "") != "noxflow-sidepanel")
    and ((.address // "") != "")
  ' >/dev/null 2>&1
}

active_window_in_sidecar_workspace() {
  active_window_json | jq -e --arg ws "special:${side_ws}" '
    ((.workspace.name // "") == $ws)
    and ((.address // "") != "")
  ' >/dev/null 2>&1
}

active_window_is_normal() {
  active_window_json | jq -e --arg class "$side_class" --argjson workspace "$(normal_current_workspace)" '
    ((.address // "") != "")
    and ((.class // "") != $class)
    and ((.workspace.id // 0) == $workspace)
    and (((.workspace.name // "") | startswith("special:")) | not)
  ' >/dev/null 2>&1
}

record_sidecar_window() {
  window_json="$1"
  workspace="${2:-$(current_workspace)}"
  python3 - "$state_file" "$window_json" "$workspace" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
try:
    client = json.loads(sys.argv[2])
except Exception:
    client = {}
workspace = sys.argv[3]
address = client.get("address", "")
if not address or str(client.get("class", "")).lower() == "noxflow-sidepanel":
    raise SystemExit(0)
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except Exception:
    data = {}
items = [item for item in data.get("windows", []) if item.get("address") != address]
items.append({
    "address": address,
    "class": client.get("class", ""),
    "title": client.get("title", ""),
    "from_workspace": workspace,
    "stashed_at": time.time(),
})
data["windows"] = items
path.write_text(json.dumps(data, indent=2))
PY
}

tracked_address() {
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]')"
  python3 - "$state_file" "$clients_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    clients = json.loads(sys.argv[2])
except Exception:
    clients = []
live = {
    client.get("address")
    for client in clients
    if client.get("workspace", {}).get("name") == "special:sidepanel"
    and client.get("class") != "noxflow-sidepanel"
}
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except Exception:
    data = {}
items = [item for item in data.get("windows", []) if item.get("address") in live]
data["windows"] = items
try:
    path.write_text(json.dumps(data, indent=2))
except Exception:
    pass
if items:
    print(items[-1].get("address", ""))
PY
}

move_tracked_to_workspace() {
  target_ws="$1"
  address="${2:-$(tracked_address || true)}"
  [ -n "$address" ] || return 1
  move_window_to_workspace "$address" "$target_ws" >/dev/null 2>&1 || return 1
  focus_window "$address" >/dev/null 2>&1 || true
  python3 - "$state_file" "$address" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
address = sys.argv[2]
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except Exception:
    data = {}
data["windows"] = [item for item in data.get("windows", []) if item.get("address") != address]
path.write_text(json.dumps(data, indent=2))
PY
}

show_sidecar() {
  sidepanel_visible || toggle_special_workspace "$side_ws" >/dev/null 2>&1 || true
}

hide_sidecar_if_visible() {
  sidepanel_visible && toggle_special_workspace "$side_ws" >/dev/null 2>&1 || true
}

hide_sidecar_if_empty() {
  hyprctl -j clients 2>/dev/null | jq -e --arg ws "special:${side_ws}" --arg class "$side_class" '
    [
      .[]
      | select((.workspace.name // "") == $ws)
      | select((.class // "") != $class)
    ]
    | length == 0
  ' >/dev/null 2>&1 && hide_sidecar_if_visible
}

send_active_to_sidecar() {
  local active address
  active="$(active_window_json)"
  printf '%s\n' "$active" | jq -e --argjson workspace "$(normal_current_workspace)" '
    ((.address // "") != "")
    and ((.workspace.id // 0) == $workspace)
    and (((.workspace.name // "") | startswith("special:")) | not)
  ' >/dev/null 2>&1 || return 1
  address="$(printf '%s\n' "$active" | jq -r '.address // empty' 2>/dev/null || true)"
  [ -n "$address" ] || return 1
  record_sidecar_window "$active" "$(normal_current_workspace)" >/dev/null 2>&1 || true
  move_window_to_workspace "$address" "special:${side_ws}" >/dev/null 2>&1 || return 1
  show_sidecar
  set_all_sidepanel_geometry
  sleep 0.08
  set_all_sidepanel_geometry
  focus_window "$address" >/dev/null 2>&1 || true
}

restore_address_to_current_workspace() {
  local address="$1"
  [ -n "$address" ] || return 1
  move_tracked_to_workspace "$(normal_current_workspace)" "$address" || return 1
  hide_sidecar_if_empty
}

smart_sidecar() {
  toggle_sidecar
}

toggle_sidecar() {
  local address
  if sidepanel_visible; then
    hide_sidecar_if_visible
    return 0
  fi
  ensure_sidepanel_client
  show_sidecar
  set_all_sidepanel_geometry
  sleep 0.08
  set_all_sidepanel_geometry
  address="$(sidepanel_client || true)"
  [ -n "$address" ] && focus_window "$address" >/dev/null 2>&1 || true
}

restore_all() {
  target_ws="$(normal_current_workspace)"
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]')"
  python3 - "$state_file" "$clients_json" <<'PY' | while IFS= read -r address; do
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    clients = json.loads(sys.argv[2])
except Exception:
    clients = []
live = {
    client.get("address")
    for client in clients
    if client.get("workspace", {}).get("name") == "special:sidepanel"
    and client.get("class") != "noxflow-sidepanel"
}
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except Exception:
    data = {}
items = [item for item in data.get("windows", []) if item.get("address") in live]
for item in items:
    print(item.get("address", ""))
data["windows"] = []
path.write_text(json.dumps(data, indent=2))
PY
    [ -n "$address" ] || continue
    move_window_to_workspace "$address" "$target_ws" >/dev/null 2>&1 || true
  done
}

ensure_sidepanel_client() {
  address="$(sidepanel_client || true)"
  [ -n "$address" ] && return 0

  kitty --class "$side_class" --title "Sidecar" -e zsh -lic '
    cd "$HOME"
    printf "Sidecar\n\nUse Super+\` to show or hide this shelf.\nUse Super+Shift+\` to move the focused window here.\nUse Super+Ctrl+\` to stash without opening.\nMove a focused Sidecar window back with Super+Shift+1..0.\n\n"
    exec zsh -l
  ' >/dev/null 2>&1 &

  for _ in $(seq 1 100); do
    address="$(sidepanel_client || true)"
    if [ -n "$address" ]; then
      move_window_to_workspace "$address" "special:${side_ws}" >/dev/null 2>&1 || true
      set_all_sidepanel_geometry
      return 0
    fi
    sleep 0.05
  done
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "Sidecar" "$1"
}

case "$mode" in
  toggle)
    toggle_sidecar
    ;;
  send)
    send_active_to_sidecar >/dev/null 2>&1 || true
    notify "Moved window to Sidecar and opened it"
    ;;
  stash)
    active="$(active_window_json)"
    record_sidecar_window "$active" "$(normal_current_workspace)" >/dev/null 2>&1 || true
    move_active_to_workspace "special:${side_ws}" >/dev/null 2>&1 || true
    notify "Stashed window in Sidecar"
    ;;
  restore)
    if move_tracked_to_workspace "$(normal_current_workspace)"; then
      notify "Restored most recent Sidecar window"
    else
      notify "No tracked Sidecar window to restore"
    fi
    ;;
  smart)
    smart_sidecar
    ;;
  restore-all)
    restore_all
    notify "Restored Sidecar windows"
    ;;
  *)
    echo "usage: $0 [toggle|send|stash|restore|smart|restore-all]" >&2
    exit 1
    ;;
esac
