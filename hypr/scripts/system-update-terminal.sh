#!/usr/bin/env bash
set -u

ack_file="${NOXFLOW_UPDATE_LAUNCH_ACK:-}"
if [ -n "$ack_file" ]; then
  : >"$ack_file"
fi

if [ "${NOXFLOW_UPDATE_PROBE:-0}" = "1" ]; then
  printf 'NoxFlow update terminal launch verified.\n'
  sleep 1
  exit 0
fi

update_script="${HOME}/.config/hypr/scripts/system-update.sh"
if [ ! -x "$update_script" ]; then
  printf 'System update script not found: %s\n' "$update_script"
  read -r -p 'Press enter to close' || true
  exit 1
fi

"$update_script" run
status=$?
printf '\nSystem update %s.\n' "$([ "$status" -eq 0 ] && printf 'finished' || printf 'failed')"
read -r -p 'Press enter to close' || true
exit "$status"
