#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"
STATE_FILE="$ROOT_DIR/settings/state.json"
BACKUP="$(mktemp)"
cp "$STATE_FILE" "$BACKUP"
cleanup() {
  cp "$BACKUP" "$STATE_FILE"
  rm -f "$BACKUP"
}
trap cleanup EXIT

"$SETTINGSCTL" validate
"$SETTINGSCTL" set notifications.timeout 9
value="$("$SETTINGSCTL" get notifications.timeout)"
[[ "$value" == "9" ]]
"$SETTINGSCTL" profile list >/dev/null
"$SETTINGSCTL" profile apply laptop
"$SETTINGSCTL" toggle notifications.sounds.enabled
"$SETTINGSCTL" apply sounds
"$SETTINGSCTL" apply action-center
"$SETTINGSCTL" doctor >/dev/null

echo "settings smoke test passed"
