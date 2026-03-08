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
  title="$(printf '%s\n' "$active_json" | jq -r '.title // "Window"')"

  if [ -z "$address" ] || [ -z "$workspace_id" ] || [ "$workspace_id" = "-1" ]; then
    notify "No normal window is focused"
    exit 1
  fi

  updated_state="$(
    read_state | jq \
      --arg address "$address" \
      --argjson workspace_id "$workspace_id" \
      --arg title "$title" \
      '
      map(select(.address != $address)) + [{
        address: $address,
        workspace_id: $workspace_id,
        title: $title
      }]
      '
  )"
  write_state "$updated_state"

  hyprctl dispatch movetoworkspacesilent "$minimized_ws" >/dev/null 2>&1 || true
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
  title="$(printf '%s\n' "$restored_item" | jq -r '.title // "Window"')"

  if [ -z "$address" ] || [ "$workspace_id" -le 0 ]; then
    notify "No minimized window to restore"
    exit 0
  fi

  hyprctl dispatch movetoworkspacesilent "$workspace_id,address:$address" >/dev/null 2>&1 || true
  hyprctl dispatch workspace "$workspace_id" >/dev/null 2>&1 || true
  hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1 || true
  notify "Restored: $title"
}

case "$mode" in
  minimize)
    minimize_active
    ;;
  restore)
    restore_last
    ;;
  *)
    echo "usage: $0 [minimize|restore]" >&2
    exit 1
    ;;
esac
