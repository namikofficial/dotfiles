#!/usr/bin/env sh
set -eu

# Toggle floating for the active window.
# When entering floating mode, apply a sensible default size, then cascade
# placement if other floating windows already exist on this workspace.

is_floating_before() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl -j activewindow 2>/dev/null | jq -r '.floating // false' 2>/dev/null || printf 'false'
    return 0
  fi

  # Fallback for systems without jq.
  hyprctl activewindow 2>/dev/null | awk -F': ' '/floating:/ { print $2; exit }' | {
    read -r v || true
    case "$v" in
      1|true|yes) printf 'true' ;;
      *) printf 'false' ;;
    esac
  }
}

before="$(is_floating_before)"
hyprctl dispatch togglefloating >/dev/null 2>&1 || exit 0

if [ "$before" = "false" ]; then
  hyprctl dispatch resizeactive exact 72% 78% >/dev/null 2>&1 || true
  hyprctl dispatch centerwindow >/dev/null 2>&1 || true

  # If jq is available, offset each newly floated window so multiple floating
  # apps are visible instead of perfectly stacked.
  if command -v jq >/dev/null 2>&1; then
    active_addr="$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""' 2>/dev/null || printf '')"
    active_ws_id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // -1' 2>/dev/null || printf -- '-1')"
    if [ -n "$active_addr" ] && [ "$active_ws_id" != "-1" ]; then
      other_float_count="$(
        hyprctl -j clients 2>/dev/null | jq -r \
          --arg addr "$active_addr" \
          --argjson ws "$active_ws_id" \
          '[.[] | select((.workspace.id // -1) == $ws and (.floating // false) == true and (.address // "") != $addr)] | length' \
          2>/dev/null || printf '0'
      )"

      case "$other_float_count" in
        ''|*[!0-9]*) other_float_count=0 ;;
      esac

      slot=$((other_float_count % 6))
      wave=$((other_float_count / 6))
      dx=$((slot * 44))
      dy=$((slot * 30 + wave * 20))

      if [ "$dx" -ne 0 ] || [ "$dy" -ne 0 ]; then
        hyprctl dispatch moveactive "$dx" "$dy" >/dev/null 2>&1 || true
      fi
    fi
  fi
fi
