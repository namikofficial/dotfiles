#!/usr/bin/env sh
set -eu

# Minimize / restore windows to a hidden special workspace.
#
# Fixes (2026-07-31, shell-redesign M2):
#   A. Fullscreen restore no longer swallows errors (`|| true` removed) and uses
#      a verified dispatch form.
#   B. Restore prefers workspace_id (stable) over workspace_name (can be a stale
#      custom name). Custom names are only used when they are real names, not
#      plain numeric ids.
#   C. Group-aware minimize: the active window is removed from its group first
#      so the hidden special workspace never carries a half-group.
#   D. `hypr_eval` propagates dispatch failures so "Minimize failed" /
#      "Restore failed" notifications are truthful.
#
# Fixes (2026-10-28, untracked-window bug):
#   E. The state file is guarded by an exclusive lock. Two concurrent
#      `minimize` runs used to read the same pre-state and each write a
#      single-entry array; the last write won, so the other window stayed
#      parked in the hidden workspace with no entry pointing at it.
#   F. A move is verified before the state file is committed. `hyprctl eval`
#      answers "ok" even for a stale window address, so the placement is
#      confirmed by re-reading the client's workspace instead of trusting
#      the dispatch result.
#   G. Restore no longer drops the entry before the move succeeds. On a
#      failed move the entry stays in the state file, so the window remains
#      reachable and the next restore retries it.
#   H. New `recover` mode reconciles the hidden workspace against the state
#      file and re-registers windows that were parked without an entry.
#
# Modes:
#   minimize          park the focused window in the hidden workspace
#   restore           restore the most recently minimized window
#   list              show tracked windows (and flag untracked ones)
#   recover [ws]      re-register untracked windows parked in the hidden
#                     workspace; defaults to the active workspace

mode="${1:-minimize}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/minimized-windows.json"
lock_file="${state_dir}/minimized-windows.lock"
minimized_ws="${NOXFLOW_MINIMIZED_WORKSPACE:-special:minimized}"
minimized_tail="${minimized_ws##*:}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "Window Minimize" "$1"
}

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

# Run a Lua dispatch. On success Hyprland prints "ok" on stdout, which is
# noise for callers; on failure the message is kept and surfaced on stderr so
# the "Minimize failed" / "Restore failed" notifications stay truthful.
hypr_eval() {
  hypr_eval_output="$(hyprctl eval "$1" 2>&1)" || {
    printf '%s\n' "$hypr_eval_output" >&2
    return 1
  }
  return 0
}

# Serialize every state mutation. The lock is held for the whole operation so
# that read-state -> move-window -> write-state is atomic against a second
# minimize/restore running at the same time.
acquire_state_lock() {
  mkdir -p "$state_dir"
  exec 9>"$lock_file"
  flock 9
}

# Remove the window from its group before moving it to the hidden workspace.
# Hyprland's group API: hl.dsp.window.move({ out_of_group = true }) detaches the
# focused window; the address-qualified form used here works with Hyprland's
# Lua IPC as exercised elsewhere in this repo (sidepanel.sh).
leave_group() {
  address="$1"
  address_lua="$(lua_string "address:$address")"
  hypr_eval "hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = ${address_lua} }))" || true
}

# Resolve a workspace name or id to the numeric id Hyprland reports.
workspace_id_for() {
  target="$1"
  hyprctl -j workspaces 2>/dev/null | jq -r --arg t "$target" '
    [ .[] | select((.id | tostring) == $t or (.name // "") == $t) | (.id | tostring) ]
    | first // empty'
}

# One lookup for both the numeric id and the name of a client's workspace.
client_workspace() {
  address="$1"
  hyprctl -j clients 2>/dev/null | jq -r --arg addr "$address" '
    [ .[] | select(.address == $addr)
      | { id: (.workspace.id | tostring), name: (.workspace.name // "") } ]
    | first // empty'
}

# Compare workspace labels on their last segment so "special:minimized" and
# "minimized" are treated as the same workspace.
label_matches() {
  actual="$1"
  expected="$2"
  [ -n "$actual" ] || return 1
  [ "${actual##*:}" = "${expected##*:}" ]
}

# Confirm the window really landed on the target workspace. `hyprctl eval`
# reports "ok" even when the address is stale, so the dispatch result alone
# proves nothing; the client's own workspace is the source of truth.
verify_placement() {
  address="$1"
  target="$2"
  target_id="$3"
  attempt=0

  while [ "$attempt" -lt 15 ]; do
    client="$(client_workspace "$address")"
    actual_id="$(printf '%s\n' "$client" | jq -r '.id // empty')"
    actual_name="$(printf '%s\n' "$client" | jq -r '.name // empty')"
    if [ -n "$actual_id" ]; then
      if [ -n "$target_id" ] && [ "$actual_id" = "$target_id" ]; then
        return 0
      fi
      if label_matches "$actual_name" "$target"; then
        return 0
      fi
    fi
    attempt=$((attempt + 1))
    sleep 0.1
  done

  return 1
}

move_window_to_workspace() {
  workspace="$1"
  address="$2"
  target_id="$(workspace_id_for "$workspace")"
  workspace_lua="$(lua_string "$workspace")"
  address_lua="$(lua_string "address:$address")"

  hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = ${workspace_lua}, follow = false, window = ${address_lua} }))" || return 1
  verify_placement "$address" "$workspace" "$target_id"
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
  if ! hypr_eval "hl.dispatch(hl.dsp.window.fullscreen({ mode = ${mode_lua}, action = \"set\", window = ${address_lua} }))"; then
    notify "Fullscreen restore failed"
    return 1
  fi
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

# Entries whose window no longer exists are pruned; they can never be
# restored and only make the state file lie about what is hidden.
prune_dead() {
  state="$1"
  clients_json="$2"
  printf '%s\n' "$state" | jq --argjson clients "$clients_json" '
    def client_for($addr): ($clients[] | select(.address == $addr));
    [ .[] | select(client_for(.address) != null) ]'
}

# The restore candidate: tracked windows newest-first, then recovered ones.
# Recovered entries are appended last so a window the user minimized by hand
# never jumps ahead of the one they just minimized.
restore_candidate() {
  state="$1"
  clients_json="$2"
  printf '%s\n' "$state" | jq -c --argjson clients "$clients_json" '
    def client_for($addr): ($clients[] | select(.address == $addr));
    [ .[] | select(.recovered != true) ] as $tracked
    | [ .[] | select(.recovered == true) ] as $recovered
    | (($tracked | reverse) + $recovered) as $ordered
    | ([ $ordered[] | select(client_for(.address) != null) ][0]) // null'
}

minimize_active() {
  active_json="$(hyprctl -j activewindow 2>/dev/null || printf '{}\n')"
  address="$(printf '%s\n' "$active_json" | jq -r '.address // empty')"
  workspace_id="$(printf '%s\n' "$active_json" | jq -r '.workspace.id // empty')"
  workspace_name="$(printf '%s\n' "$active_json" | jq -r '.workspace.name // empty')"
  fullscreen_state="$(printf '%s\n' "$active_json" | jq -r '.fullscreen // 0')"
  title="$(printf '%s\n' "$active_json" | jq -r '.title // "Window"')"

  if [ -z "$address" ] || [ -z "$workspace_id" ] || [ "$workspace_id" -le 0 ]; then
    notify "No normal window is focused"
    exit 1
  fi

  if label_matches "$workspace_name" "$minimized_ws"; then
    notify "Window is already minimized"
    exit 1
  fi

  now="$(date +%s)"

  # The new state is computed under the lock but committed only after the
  # window is verifiably parked, so a failed move cannot leave a stale entry.
  updated_state="$(
    read_state | jq \
      --arg address "$address" \
      --argjson workspace_id "$workspace_id" \
      --arg workspace_name "$workspace_name" \
      --argjson fullscreen_state "$fullscreen_state" \
      --arg title "$title" \
      --argjson now "$now" \
      '
      map(select(.address != $address)) + [{
        address: $address,
        workspace_id: $workspace_id,
        workspace_name: $workspace_name,
        fullscreen_state: $fullscreen_state,
        title: $title,
        minimized_at: $now
      }]
      '
  )"

  # Group-aware: detach the window from its group before hiding it.
  leave_group "$address"

  unset_window_fullscreen "$address"
  if ! move_window_to_workspace "$minimized_ws" "$address"; then
    notify "Minimize failed"
    exit 1
  fi

  write_state "$updated_state"
  notify "Minimized: $title"
}

restore_last() {
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]\n')"
  state="$(read_state)"

  restored_item="$(restore_candidate "$state" "$clients_json")"
  address="$(printf '%s\n' "$restored_item" | jq -r '.address // empty')"
  workspace_id="$(printf '%s\n' "$restored_item" | jq -r '.workspace_id // 0')"
  workspace_name="$(printf '%s\n' "$restored_item" | jq -r '.workspace_name // empty')"
  fullscreen_state="$(printf '%s\n' "$restored_item" | jq -r '.fullscreen_state // 0')"
  title="$(printf '%s\n' "$restored_item" | jq -r '.title // "Window"')"

  if [ -z "$address" ]; then
    write_state "$(prune_dead "$state" "$clients_json")"
    notify "No minimized window to restore"
    exit 0
  fi

  # Restore by numeric workspace id when the name is just the id as a string;
  # only use a real custom name (non-numeric) as the target.
  case "$workspace_name" in
    '' | *[!0-9]*)
      target_workspace="$workspace_name"
      ;;
    *)
      target_workspace="$workspace_id"
      ;;
  esac
  [ -n "$target_workspace" ] || target_workspace="$workspace_id"

  if ! move_window_to_workspace "$target_workspace" "$address"; then
    # Keep the entry: the window is still parked in the hidden workspace, and
    # dropping the entry here is what made such windows unreachable.
    notify "Restore failed"
    exit 1
  fi

  focus_workspace "$target_workspace" || true
  focus_window "$address" || true
  set_window_fullscreen "$address" "$fullscreen_state"

  write_state "$(
    printf '%s\n' "$state" | jq --argjson clients "$clients_json" --arg addr "$address" '
      def client_for($a): ($clients[] | select(.address == $a));
      [ .[] | select(.address != $addr) | select(client_for(.address) != null) ]
    '
  )"
  notify "Restored: $title"
}

list_state() {
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]\n')"
  state="$(read_state)"

  live_state="$(prune_dead "$state" "$clients_json")"
  write_state "$live_state"

  printf '%s\n' "$live_state" | jq -r '.[] | "\(.address)\tworkspace=\(.workspace_name // .workspace_id)\t\(.title // "Window")"'

  # Untracked windows are parked in the hidden workspace but have no entry, so
  # `restore` can never reach them. Surface them instead of hiding the bug.
  untracked="$(
    printf '%s\n' "$live_state" | jq -r --argjson clients "$clients_json" --arg ws "$minimized_ws" '
      [ .[] | .address ] as $tracked
      | [ $clients[]
          | select((.workspace.name // "") == $ws)
          | select((.address as $a | any($tracked[]; . == $a)) | not)
          | "\(.address)\tUNTRACKED\t\(.title // "Window")" ]
      | .[]
    '
  )"
  if [ -n "$untracked" ]; then
    printf '%s\n' "$untracked"
  fi
}

# Re-register windows that are parked in the hidden workspace without a state
# entry. Their original workspace is unknown, so they are restored to the
# requested workspace (default: the active one).
recover_orphans() {
  target="${1:-}"
  clients_json="$(hyprctl -j clients 2>/dev/null || printf '[]\n')"
  state="$(read_state)"

  if [ -n "$target" ]; then
    target_id="$(workspace_id_for "$target")"
    if [ -z "$target_id" ]; then
      notify "Unknown workspace: $target"
      exit 1
    fi
    target_name="$target"
  else
    active_json="$(hyprctl -j activeworkspace 2>/dev/null || printf '{}\n')"
    target_id="$(printf '%s\n' "$active_json" | jq -r '.id // empty')"
    target_name="$(printf '%s\n' "$active_json" | jq -r '.name // empty')"
    if [ -z "$target_id" ]; then
      notify "No active workspace to recover into"
      exit 1
    fi
  fi

  now="$(date +%s)"
  recovered="$(
    printf '%s\n' "$state" | jq \
      --argjson clients "$clients_json" \
      --arg ws "$minimized_ws" \
      --arg target_name "$target_name" \
      --argjson target_id "$target_id" \
      --argjson now "$now" \
      '
    [ .[] | .address ] as $tracked
    | ([ $clients[]
          | select((.workspace.name // "") == $ws)
          | select((.address as $a | any($tracked[]; . == $a)) | not)
          | {
              address: .address,
              workspace_id: $target_id,
              workspace_name: $target_name,
              fullscreen_state: (.fullscreen // 0),
              title: (.title // "Window"),
              minimized_at: $now,
              recovered: true
            } ]) as $orphans
    | $orphans
    '
  )"

  count="$(printf '%s\n' "$recovered" | jq -r 'length')"
  if [ "$count" -eq 0 ]; then
    notify "No untracked minimized windows"
    exit 0
  fi

  write_state "$(printf '%s\n' "$state" | jq --argjson orphans "$recovered" '. + $orphans')"

  printf '%s\n' "$recovered" | jq -r '.[] | "Recovered: \(.title) -> workspace \(.workspace_name)"'
  notify "Recovered $count minimized window(s)"
}

case "$mode" in
  minimize)
    acquire_state_lock
    minimize_active
    ;;
  restore)
    acquire_state_lock
    restore_last
    ;;
  list)
    acquire_state_lock
    list_state
    ;;
  recover)
    acquire_state_lock
    recover_orphans "${2:-}"
    ;;
  *)
    echo "usage: $0 [minimize|restore|list|recover [workspace]]" >&2
    exit 1
    ;;
esac
