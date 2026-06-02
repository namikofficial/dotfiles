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

move_window_to_workspace() {
  address="$1"
  workspace="$2"
  [ -n "$address" ] || return 0
  address_lua="$(lua_string "address:$address")"
  ws_lua="$(lua_string "$workspace")"
  hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = ${ws_lua}, follow = false, window = ${address_lua} }))"
}

sidepanel_geometry() {
  hyprctl -j monitors 2>/dev/null | jq -r '
    (map(select(.focused == true))[0] // .[0] // {}) as $m
    | ($m.reserved // [0, 0, 0, 0]) as $r
    | ($m.x // 0) as $mx
    | ($m.y // 0) as $my
    | (($r[0] // 0) | tonumber) as $left
    | (($r[1] // 0) | tonumber) as $top
    | (($r[2] // 0) | tonumber) as $right
    | (($r[3] // 0) | tonumber) as $bottom
    | (($m.width // 1600) - $left - $right) as $usable_w
    | (($m.height // 900) - $top - $bottom) as $usable_h
    | ([$usable_w * 0.34 | floor, 460] | max) as $w
    | ([$usable_h * 0.92 | floor, 520] | max) as $h
    | ($mx + $left + $usable_w - $w - 14) as $x
    | ($my + $top + (($usable_h - $h) / 2 | floor)) as $y
    | "\($x|floor) \($y|floor) \($w|floor) \($h|floor)"
  ' 2>/dev/null || printf '1000 60 620 820\n'
}

set_sidepanel_geometry() {
  address="$1"
  [ -n "$address" ] || return 0
  read -r x y w h <<EOF_GEOM
$(sidepanel_geometry)
EOF_GEOM
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.window.float({ state = true, window = ${address_lua} }))" || return 1
  hypr_eval "hl.dispatch(hl.dsp.window.resize({ x = ${w}, y = ${h}, window = ${address_lua} }))" || return 1
  hypr_eval "hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, window = ${address_lua} }))" || return 1
}

focus_window() {
  address="$1"
  [ -n "$address" ] || return 0
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.focus({ window = ${address_lua} }))"
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
  hyprctl -j clients 2>/dev/null | python3 - "$state_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    clients = json.load(sys.stdin)
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
  set_sidepanel_geometry "$address" >/dev/null 2>&1 || true
  focus_window "$address" >/dev/null 2>&1 || true
}

restore_address_to_current_workspace() {
  local address="$1"
  [ -n "$address" ] || return 1
  move_tracked_to_workspace "$(normal_current_workspace)" "$address" || return 1
  hide_sidecar_if_empty
}

smart_sidecar() {
  local address
  if active_window_in_sidecar_workspace; then
    if sidepanel_visible; then
      hide_sidecar_if_visible
      notify "Hid Sidecar"
      return 0
    fi
  fi
  if active_window_is_normal; then
    if send_active_to_sidecar; then
      notify "Moved window to Sidecar"
      return 0
    fi
  fi
  address="$(tracked_address || true)"
  if [ -n "$address" ]; then
    if restore_address_to_current_workspace "$address"; then
      notify "Restored most recent Sidecar window"
      return 0
    fi
  fi
  if sidepanel_visible; then
    hide_sidecar_if_visible
  else
    ensure_sidepanel_client
    show_sidecar
    address="$(sidepanel_client || true)"
    [ -n "$address" ] && set_sidepanel_geometry "$address" >/dev/null 2>&1 || true
    [ -n "$address" ] && focus_window "$address" >/dev/null 2>&1 || true
  fi
}

restore_all() {
  target_ws="$(normal_current_workspace)"
  hyprctl -j clients 2>/dev/null | python3 - "$state_file" <<'PY' | while IFS= read -r address; do
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    clients = json.load(sys.stdin)
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
    printf "Sidecar\n\nUse Super+\` to send, hide, or restore latest.\nUse Super+Ctrl+\` to stash without opening.\nUse Super+Shift+\` to restore the most recent window.\nUse Super+Alt+\` to show or hide this shelf.\nMove a focused Sidecar window with Super+Shift+1..0.\n\n"
    exec zsh -l
  ' >/dev/null 2>&1 &

  for _ in $(seq 1 100); do
    address="$(sidepanel_client || true)"
    if [ -n "$address" ]; then
      move_window_to_workspace "$address" "special:${side_ws}" >/dev/null 2>&1 || true
      set_sidepanel_geometry "$address" >/dev/null 2>&1 || true
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
    if sidepanel_visible; then
      toggle_special_workspace "$side_ws" >/dev/null 2>&1 || true
    else
      ensure_sidepanel_client
      toggle_special_workspace "$side_ws" >/dev/null 2>&1 || true
      address="$(sidepanel_client || true)"
      [ -n "$address" ] && set_sidepanel_geometry "$address" >/dev/null 2>&1 || true
      [ -n "$address" ] && focus_window "$address" >/dev/null 2>&1 || true
    fi
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
