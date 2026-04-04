#!/usr/bin/env bash
set -euo pipefail

log_lib="$HOME/.config/hypr/scripts/lib/log.sh"

command -v dbus-monitor >/dev/null 2>&1 || exit 0
[ -x "$log_lib" ] || exit 0

emit() {
  local app="$1" summary="$2" body="$3"
  local sev="info"
  case "$summary $body" in
    *error*|*Error*|*failed*|*Failed*) sev="error" ;;
    *warn*|*Warn*|*warning*|*Warning*) sev="warn" ;;
  esac
  "$log_lib" --emit "$sev" "dbus-notify" "$summary" "$body" "$app" "$body" >/dev/null 2>&1 || true
}

app=""
summary=""
body=""
str_idx=0
in_notify=0

# shellcheck disable=SC2016
dbus-monitor --session "interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null |
while IFS= read -r line; do
  case "$line" in
    *"member=Notify"*)
      in_notify=1
      str_idx=0
      app=""
      summary=""
      body=""
      ;;
    *)
      ;;
  esac

  [ "$in_notify" -eq 1 ] || continue

  if [[ "$line" =~ string\ \"(.*)\" ]]; then
    value="${BASH_REMATCH[1]}"
    str_idx=$((str_idx + 1))
    case "$str_idx" in
      1) app="$value" ;;
      3) summary="$value" ;;
      4)
        body="$value"
        if [ -n "$summary" ]; then
          emit "$app" "$summary" "$body"
        fi
        in_notify=0
        ;;
    esac
  fi
done
