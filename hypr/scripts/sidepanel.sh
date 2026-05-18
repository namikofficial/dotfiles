#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
side_ws="sidepanel"
side_class="noxflow-sidepanel"

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

ensure_sidepanel_client() {
  address="$(sidepanel_client || true)"
  [ -n "$address" ] && return 0

  kitty --class "$side_class" --title "Side Panel" -e zsh -lic '
    cd "$HOME"
    printf "Side Panel\n\nUse Super+Shift+\\\\ to send the focused window here.\nUse Super+Ctrl+\\\\ to stash without opening.\n\n"
    exec zsh -l
  ' >/dev/null 2>&1 &

  for _ in $(seq 1 30); do
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
  notify-send -a Hyprland "Side Panel" "$1"
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
    move_active_to_workspace "special:${side_ws}" >/dev/null 2>&1 || true
    sidepanel_visible || toggle_special_workspace "$side_ws" >/dev/null 2>&1 || true
    notify "Moved window to side panel and opened it"
    ;;
  stash)
    move_active_to_workspace "special:${side_ws}" >/dev/null 2>&1 || true
    notify "Moved window to side panel"
    ;;
  *)
    echo "usage: $0 [toggle|send|stash]" >&2
    exit 1
    ;;
esac
