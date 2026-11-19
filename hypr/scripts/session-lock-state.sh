#!/usr/bin/env bash
set -euo pipefail

command -v loginctl >/dev/null 2>&1 || exit 1
command -v id >/dev/null 2>&1 || exit 1

sessions="$(loginctl show-user "$(id -u)" -p Sessions --value 2>/dev/null)" || exit 1
found_graphical_session=0

for session in $sessions; do
  properties="$(loginctl show-session "$session" -p Type -p State -p LockedHint --value 2>/dev/null)" || continue
  mapfile -t session_properties <<<"$properties"
  session_type="${session_properties[0]:-}"
  session_state="${session_properties[1]:-}"
  locked_hint="${session_properties[2]:-}"
  case "$session_type" in
    wayland | x11) ;;
    *) continue ;;
  esac
  [ "$session_state" = "active" ] || continue
  found_graphical_session=1
  if [ "$locked_hint" != "no" ]; then
    printf 'yes\n'
    exit 0
  fi
done

[ "$found_graphical_session" -eq 1 ] || exit 1
printf 'no\n'
