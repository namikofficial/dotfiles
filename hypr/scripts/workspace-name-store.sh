#!/usr/bin/env sh
set -eu

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/workspace-names.json"

usage() {
  cat <<'USAGE' >&2
usage: workspace-name-store.sh <command> [args]

commands:
  set <workspace_id> <name>
  get <workspace_id>
  unset <workspace_id>
  list
  json
USAGE
  exit 1
}

ensure_state_dir() {
  mkdir -p "$state_dir"
}

is_valid_ws_id() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

read_state_json() {
  if [ ! -f "$state_file" ]; then
    printf '{}\n'
    return 0
  fi

  if jq -e 'type == "object"' "$state_file" >/dev/null 2>&1; then
    cat "$state_file"
    return 0
  fi

  # Graceful fallback for malformed state.
  printf '{}\n'
}

write_state_json() {
  json_payload="$1"
  ensure_state_dir

  tmp_file="${state_file}.tmp.$$"
  printf '%s\n' "$json_payload" >"$tmp_file"
  mv "$tmp_file" "$state_file"
}

normalize_name() {
  raw="$1"
  trimmed="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  cleaned="$(printf '%s' "$trimmed" | tr '\t\r\n' '   ' | sed -e 's/  */ /g')"
  printf '%s' "$cleaned"
}

cmd_set() {
  [ "$#" -ge 2 ] || usage
  ws_id="$1"
  shift

  is_valid_ws_id "$ws_id" || {
    echo "workspace-name-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  name="$(normalize_name "$*")"
  [ -n "$name" ] || {
    echo "workspace-name-store: name cannot be empty" >&2
    exit 1
  }

  name_len="$(printf '%s' "$name" | wc -m | tr -d ' ')"
  [ "$name_len" -le 32 ] || {
    echo "workspace-name-store: name too long (max 32 chars)" >&2
    exit 1
  }

  state_json="$(read_state_json)"
  updated_json="$(printf '%s' "$state_json" | jq --arg ws "$ws_id" --arg name "$name" '.[$ws] = $name')"
  write_state_json "$updated_json"
}

cmd_get() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"

  is_valid_ws_id "$ws_id" || {
    echo "workspace-name-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  state_json="$(read_state_json)"
  printf '%s' "$state_json" | jq -r --arg ws "$ws_id" '.[$ws] // empty'
}

cmd_unset() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"

  is_valid_ws_id "$ws_id" || {
    echo "workspace-name-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  state_json="$(read_state_json)"
  updated_json="$(printf '%s' "$state_json" | jq --arg ws "$ws_id" 'del(.[$ws])')"
  write_state_json "$updated_json"
}

cmd_list() {
  [ "$#" -eq 0 ] || usage
  read_state_json | jq -r 'to_entries | sort_by(.key|tonumber) | .[] | "\(.key)\t\(.value)"'
}

cmd_json() {
  [ "$#" -eq 0 ] || usage
  read_state_json
}

[ "$#" -ge 1 ] || usage

command="$1"
shift

case "$command" in
  set) cmd_set "$@" ;;
  get) cmd_get "$@" ;;
  unset) cmd_unset "$@" ;;
  list) cmd_list "$@" ;;
  json|dump) cmd_json "$@" ;;
  *) usage ;;
esac
