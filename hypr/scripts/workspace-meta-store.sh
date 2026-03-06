#!/usr/bin/env sh
set -eu

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/workspace-meta.json"
recent_max="${WORKSPACE_RECENT_MAX:-3}"

usage() {
  cat <<'USAGE' >&2
usage: workspace-meta-store.sh <command> [args]

commands:
  favorite-toggle <workspace_id>
  favorite-add <workspace_id>
  favorite-remove <workspace_id>
  favorite-list
  recent-push <workspace_id>
  recent-list
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
    printf '{"favorites":[],"recent":[]}\n'
    return 0
  fi

  if jq -e 'type == "object"' "$state_file" >/dev/null 2>&1; then
    cat "$state_file"
    return 0
  fi

  printf '{"favorites":[],"recent":[]}\n'
}

write_state_json() {
  json_payload="$1"
  ensure_state_dir
  tmp_file="${state_file}.tmp.$$"
  printf '%s\n' "$json_payload" >"$tmp_file"
  mv "$tmp_file" "$state_file"
}

normalized_state() {
  read_state_json | jq '
    {
      favorites: ((.favorites // []) | map(select(type == "number" and . > 0)) | unique),
      recent: ((.recent // []) | map(select(type == "number" and . > 0)) | unique)
    }
  '
}

cmd_favorite_add() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"
  is_valid_ws_id "$ws_id" || {
    echo "workspace-meta-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  updated="$(normalized_state | jq --argjson ws "$ws_id" '.favorites = ((.favorites + [$ws]) | unique | sort)')"
  write_state_json "$updated"
}

cmd_favorite_remove() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"
  is_valid_ws_id "$ws_id" || {
    echo "workspace-meta-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  updated="$(normalized_state | jq --argjson ws "$ws_id" '.favorites = (.favorites | map(select(. != $ws)))')"
  write_state_json "$updated"
}

cmd_favorite_toggle() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"
  is_valid_ws_id "$ws_id" || {
    echo "workspace-meta-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  updated="$(normalized_state | jq --argjson ws "$ws_id" '
    if (.favorites | index($ws)) == null then
      .favorites = ((.favorites + [$ws]) | unique)
    else
      .favorites = (.favorites | map(select(. != $ws)))
    end
  ')"
  write_state_json "$updated"
}

cmd_recent_push() {
  [ "$#" -eq 1 ] || usage
  ws_id="$1"
  is_valid_ws_id "$ws_id" || {
    echo "workspace-meta-store: invalid workspace id '$ws_id'" >&2
    exit 1
  }

  max=3
  if [ "$recent_max" -ge 1 ] 2>/dev/null; then
    max="$recent_max"
  fi

  updated="$(normalized_state | jq --argjson ws "$ws_id" --argjson max "$max" '
    .recent = (([$ws] + (.recent | map(select(. != $ws)))) | .[:$max])
  ')"
  write_state_json "$updated"
}

cmd_favorite_list() {
  [ "$#" -eq 0 ] || usage
  normalized_state | jq -r '.favorites[]?'
}

cmd_recent_list() {
  [ "$#" -eq 0 ] || usage
  normalized_state | jq -r '.recent[]?'
}

cmd_json() {
  [ "$#" -eq 0 ] || usage
  normalized_state
}

[ "$#" -ge 1 ] || usage

command="$1"
shift

case "$command" in
  favorite-toggle) cmd_favorite_toggle "$@" ;;
  favorite-add) cmd_favorite_add "$@" ;;
  favorite-remove) cmd_favorite_remove "$@" ;;
  favorite-list) cmd_favorite_list "$@" ;;
  recent-push) cmd_recent_push "$@" ;;
  recent-list) cmd_recent_list "$@" ;;
  json|dump) cmd_json "$@" ;;
  *) usage ;;
esac
