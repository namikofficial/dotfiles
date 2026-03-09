#!/usr/bin/env sh
set -eu

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/noxflow"
STATE_FILE="$STATE_DIR/drm-connectors.state"
mkdir -p "$STATE_DIR"

snapshot_connectors() {
  for path in /sys/class/drm/card*-*/status; do
    [ -e "$path" ] || continue
    connector="${path%/status}"
    connector="${connector##*/}"
    status="$(cat "$path" 2>/dev/null || printf 'unknown')"
    printf '%s=%s\n' "$connector" "$status"
  done | sort
}

maybe_reload() {
  status_blob="$1"

  # Give the kernel a moment to settle on hotplug before reloading outputs.
  sleep 1

  if printf '%s\n' "$status_blob" | grep -q 'connected'; then
    hyprctl reload >/dev/null 2>&1 || true
    hyprctl dispatch dpms on >/dev/null 2>&1 || true
  else
    hyprctl reload >/dev/null 2>&1 || true
  fi
}

prev="$(snapshot_connectors)"
printf '%s\n' "$prev" > "$STATE_FILE"

while :; do
  sleep 2
  current="$(snapshot_connectors)"
  [ "$current" = "$prev" ] && continue

  printf '%s\n' "$current" > "$STATE_FILE"
  prev="$current"
  maybe_reload "$current"
done
