#!/usr/bin/env sh
set -eu

mode="${1:-minimize}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/minimized-windows.json"
minimized_ws="${NOXFLOW_MINIMIZED_WORKSPACE:-special:minimized}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "Window Minimize" "$1"
}

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

hypr_eval() {
  hyprctl eval "$1" >/dev/null
}

move_window_to_workspace() {
  workspace="$1"
  address="$2"
  workspace_lua="$(lua_string "$workspace")"
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = ${workspace_lua}, follow = false, window = ${address_lua} }))"
}

focus_workspace() {
  workspace="$1"
  workspace_lua="$(lua_string "$workspace")"
  hypr_eval "hl.dispatch(hl.dsp.focus({ workspace = ${workspace_lua} }))"
}

focus_window() {
  address="$1"
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.focus({ window = ${address_lua} }))"
}

set_window_fullscreen() {
  address="$1"
  fullscreen_state="$2"
  mode=""

  case "$fullscreen_state" in
    1) mode="maximized" ;;
    2 | 3) mode="fullscreen" ;;
    *) return 0 ;;
  esac

  address_lua="$(lua_string "address:$address")"
  mode_lua="$(lua_string "$mode")"
  hypr_eval "hl.dispatch(hl.dsp.window.fullscreen({ mode = ${mode_lua}, action = \"set\", window = ${address_lua} }))" || true
}

unset_window_fullscreen() {
  address="$1"
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.window.fullscreen({ action = \"unset\", window = ${address_lua} }))" || true
}

ensure_state_dir() {
  mkdir -p "$state_dir"
}

read_state() {
  if [ ! -f "$state_file" ]; then
    printf '[]\n'
    return 0
  fi

  if jq -e 'type == "array"' "$state_file" >/dev/null 2>&1; then
    cat "$state_file"
    return 0
  fi

  printf '[]\n'
}

write_state() {
  payload="$1"
  ensure_state_dir
  tmp_file="${state_file}.tmp.$$"
  printf '%s\n' "$payload" >"$tmp_file"
  mv "$tmp_file" "$state_file"
}

minimize_active() {
  active_json="$(hyprctl -j activewindow 2>/dev/null || printf '{}\n')"
  address="$(printf '%s\n' "$active_json" | jq -r '.address // empty')"
  workspace_id="$(printf '%s\n' "$active_json" | jq -r '.workspace.id // empty')"
  workspace_name="$(printf '%s\n' "$active_json" | jq -r '.workspace.name // empty')"
  fullscreen_state="$(printf '%s\n' "$active_json" | jq -r '.fullscreen // 0')"
  title="$(printf '%s\n' "$active_json" | jq -r '.title // "Window"')"

  if [ -z "$address" ] || [ -z "$workspace_id" ] || [ "$workspace_id" = "-1" ] || [ "$workspace_name" = "${minimized_ws#special:}" ]; then
    notify "No normal window is focused"
    exit 1
  fi

  updated_state="$(
    read_state | jq \
      --arg address "$address" \
      --argjson workspace_id "$workspace_id" \
      --arg workspace_name "$workspace_name" \
      --argjson fullscreen_state "$fullscreen_state" \
      --arg title "$title" \
      '
      map(select(.address != $address)) + [{
        address: $address,
        workspace_id: $workspace_id,
        workspace_name: $workspace_name,
        fullscreen_state: $fullscreen_state,
        title: $title
      }]
      '
  )"
  write_state "$updated_state"

  unset_window_fullscreen "$address"
  if ! move_window_to_workspace "$minimized_ws" "$address"; then
    notify "Minimize failed"
    exit 1
  fi
  notify "Minimized: $title"
}

restore_last() {
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]\n')"

  restored="$(
    read_state | jq -c --argjson clients "$clients_json" '
      def client_for($addr):
        ($clients[] | select(.address == $addr));

      reduce reverse .[] as $item (
        {restored: null, remaining: []};
        if .restored != null then
          .remaining = [$item] + .remaining
        else
          (try client_for($item.address) catch null) as $client
          | if $client == null then
              .
            else
              .restored = {
                address: $item.address,
                workspace_id: ($item.workspace_id // 0),
                workspace_name: ($item.workspace_name // (($item.workspace_id // 0) | tostring)),
                fullscreen_state: ($item.fullscreen_state // 0),
                title: ($item.title // ($client.title // "Window"))
              }
            end
        end
      )
      '
  )"

  restored_item="$(printf '%s\n' "$restored" | jq -c '.restored')"
  remaining_state="$(printf '%s\n' "$restored" | jq '.remaining')"
  write_state "$remaining_state"

  address="$(printf '%s\n' "$restored_item" | jq -r '.address // empty')"
  workspace_id="$(printf '%s\n' "$restored_item" | jq -r '.workspace_id // 0')"
  workspace_name="$(printf '%s\n' "$restored_item" | jq -r '.workspace_name // empty')"
  fullscreen_state="$(printf '%s\n' "$restored_item" | jq -r '.fullscreen_state // 0')"
  title="$(printf '%s\n' "$restored_item" | jq -r '.title // "Window"')"

  if [ -z "$address" ] || [ "$workspace_id" -le 0 ]; then
    notify "No minimized window to restore"
    exit 0
  fi

  target_workspace="${workspace_name:-$workspace_id}"
  if ! move_window_to_workspace "$target_workspace" "$address"; then
    notify "Restore failed"
    exit 1
  fi
  focus_workspace "$target_workspace" || true
  focus_window "$address" || true
  set_window_fullscreen "$address" "$fullscreen_state"
  notify "Restored: $title"
}

list_state() {
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]\n')"
  live_state="$(
    read_state | jq --argjson clients "$clients_json" '
      map(select(.address as $addr | any($clients[]; .address == $addr)))
    '
  )"
  write_state "$live_state"
  printf '%s\n' "$live_state" | jq -r '.[] | "\(.address)\tworkspace=\(.workspace_name // .workspace_id)\t\(.title // "Window")"'
}

case "$mode" in
  minimize)
    minimize_active
    ;;
  restore)
    restore_last
    ;;
  list)
    list_state
    ;;
  *)
    echo "usage: $0 [minimize|restore|list]" >&2
    exit 1
    ;;
esac
