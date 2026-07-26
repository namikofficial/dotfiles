#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"
STATE_FILE="$ROOT_DIR/settings/state.json"
BACKUP="$(mktemp)"
cp "$STATE_FILE" "$BACKUP"
LOCAL_STATE_FILE="$ROOT_DIR/settings/state.local.json"
LOCAL_BACKUP="$(mktemp)"
LOCAL_EXISTED=0
if [[ -f "$LOCAL_STATE_FILE" ]]; then
  cp "$LOCAL_STATE_FILE" "$LOCAL_BACKUP"
  LOCAL_EXISTED=1
fi
cleanup() {
  cp "$BACKUP" "$STATE_FILE"
  rm -f "$BACKUP"
  if ((LOCAL_EXISTED)); then
    cp "$LOCAL_BACKUP" "$LOCAL_STATE_FILE"
  else
    rm -f "$LOCAL_STATE_FILE"
  fi
  rm -f "$LOCAL_BACKUP"
}
trap cleanup EXIT

"$SETTINGSCTL" validate
"$SETTINGSCTL" set notifications.timeout 9
value="$("$SETTINGSCTL" get notifications.timeout)"
[[ "$value" == "9" ]]
"$SETTINGSCTL" profile list >/dev/null
for profile in laptop cinematic balanced reduced-motion battery; do
  "$SETTINGSCTL" profile apply "$profile"
  "$SETTINGSCTL" apply animations >/dev/null
  [[ "$("$SETTINGSCTL" get animations.profile)" != "null" ]]
done
"$SETTINGSCTL" profile apply laptop
"$SETTINGSCTL" toggle notifications.sounds.enabled
"$SETTINGSCTL" apply sounds
"$SETTINGSCTL" apply action-center
"$SETTINGSCTL" doctor >/dev/null

echo "settings smoke test passed"
