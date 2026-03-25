#!/usr/bin/env bash
set -euo pipefail

cfg="$HOME/.config/eww"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"
last_seen=""

command -v jq >/dev/null 2>&1 || exit 0
command -v eww >/dev/null 2>&1 || exit 0
[ -f "$cfg/eww.yuck" ] || exit 0

eww --config "$cfg" daemon >/dev/null 2>&1 || true

while :; do
  if [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
    sleep 1
    continue
  fi

  mode="$(jq -r '.mode // "custom"' "$state_file")"
  [ "$mode" = "custom" ] || { sleep 1; continue; }

  current_id="$(jq -r '.events[0].id // ""' "$state_file")"
  [ -n "$current_id" ] || { sleep 1; continue; }

  if [ "$current_id" != "$last_seen" ]; then
    sev="$(jq -r '.events[0].severity // "info"' "$state_file")"
    case "$sev" in
      critical) dur=10 ;;
      error) dur=7 ;;
      warn) dur=5 ;;
      *) dur=4 ;;
    esac

    eww --config "$cfg" open notif_toast >/dev/null 2>&1 || true
    last_seen="$current_id"

    i=0
    while [ "$i" -lt "$dur" ]; do
      sleep 1
      newest="$(jq -r '.events[0].id // ""' "$state_file" 2>/dev/null || echo "")"
      [ "$newest" = "$last_seen" ] || break
      i=$((i + 1))
    done

    newest="$(jq -r '.events[0].id // ""' "$state_file" 2>/dev/null || echo "")"
    if [ "$newest" = "$last_seen" ]; then
      eww --config "$cfg" close notif_toast >/dev/null 2>&1 || true
    fi
  fi

  sleep 1
done
