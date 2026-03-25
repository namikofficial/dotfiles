#!/usr/bin/env bash
set -euo pipefail

NOTIF_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif"
EVENTS_FILE="$NOTIF_DIR/events.jsonl"
STATE_FILE="$NOTIF_DIR/state.json"
MAX_EVENTS="${HYPR_NOTIF_MAX_EVENTS:-160}"
LOG_DIR="${NOXFLOW_LOG_DIR:-$HOME/Documents/code/dotfiles/logs/hypr}"

notif_init() {
  mkdir -p "$NOTIF_DIR" "$LOG_DIR"
  [ -f "$EVENTS_FILE" ] || : > "$EVENTS_FILE"
  if [ ! -s "$STATE_FILE" ]; then
    cat > "$STATE_FILE" <<JSON
{"mode":"custom","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}
JSON
  fi
}

_log_line() {
  local level="$1" component="$2" message="$3"
  local now file
  now="$(date -Iseconds)"
  file="$LOG_DIR/${component}-$(date +%Y%m%d).log"
  printf '%s level=%s pid=%s component=%s msg=%s\n' "$now" "$level" "$$" "$component" "$message" >> "$file"
}

_event_id() {
  printf '%s-%s-%s' "$(date +%s%N)" "$RANDOM" "$$"
}

_state_json() {
  if command -v jq >/dev/null 2>&1 && [ -s "$STATE_FILE" ] && jq . "$STATE_FILE" >/dev/null 2>&1; then
    cat "$STATE_FILE"
  else
    printf '{"mode":"custom","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}'
  fi
}

write_event() {
  local severity="$1"
  local component="$2"
  local title="$3"
  local body="${4:-}"
  local details="${5:-}"
  local copy_payload="${6:-}"
  local actions_json="${7:-[]}"

  notif_init

  if ! command -v jq >/dev/null 2>&1; then
    _log_line "$severity" "$component" "$title $body"
    return 0
  fi

  local id now event tmp
  id="$(_event_id)"
  now="$(date -Iseconds)"

  event="$(jq -nc \
    --arg id "$id" \
    --arg time "$now" \
    --arg severity "$severity" \
    --arg component "$component" \
    --arg title "$title" \
    --arg body "$body" \
    --arg details "$details" \
    --arg payload "$copy_payload" \
    --argjson actions "$actions_json" \
    '{id:$id,time:$time,severity:$severity,component:$component,title:$title,body:$body,details:$details,copiable_payload:$payload,actions:$actions}')"

  printf '%s\n' "$event" >> "$EVENTS_FILE"

  tmp="$(mktemp)"
  _state_json | jq --argjson ev "$event" --argjson max "$MAX_EVENTS" '
    .mode = (.mode // "custom")
    | .dnd = (.dnd // false)
    | .events = ([ $ev ] + (.events // []))[:$max]
    | .selected_index = 0
    | .selected_id = $ev.id
    | .last_id = $ev.id
    | .updated_at = $ev.time
  ' > "$tmp"
  mv "$tmp" "$STATE_FILE"

  _log_line "$severity" "$component" "$title $body"
}

log_info() { _log_line "info" "$1" "${2:-}"; }
log_warn() { _log_line "warn" "$1" "${2:-}"; }
log_error() { _log_line "error" "$1" "${2:-}"; }

notify_info() {
  local component="$1" title="$2" body="${3:-}" details="${4:-}" payload="${5:-}"
  write_event "info" "$component" "$title" "$body" "$details" "$payload" '[]'
}

notify_warn() {
  local component="$1" title="$2" body="${3:-}" details="${4:-}" payload="${5:-}"
  write_event "warn" "$component" "$title" "$body" "$details" "$payload" '[]'
}

notify_error() {
  local component="$1" title="$2" body="${3:-}" details="${4:-}" payload="${5:-}"
  write_event "error" "$component" "$title" "$body" "$details" "$payload" '[]'
}

case "${1:-}" in
  --init)
    notif_init
    ;;
  --emit)
    shift
    write_event "${1:-info}" "${2:-manual}" "${3:-Test}" "${4:-}" "${5:-}" "${6:-}" '[]'
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [--init | --emit <sev> <component> <title> [body] [details] [payload]]" >&2
    exit 1
    ;;
esac
