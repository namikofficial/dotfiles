#!/usr/bin/env sh
set -eu

mode="${1:-print}"

media="$(wayle media status 2>/dev/null | head -n1 || echo 'idle')"
gpu="n/a"
notif_mode="wayle"
dnd="$(wayle notify status 2>/dev/null | awk -F': ' '/Do Not Disturb/ {print $2}' | tr '[:upper:]' '[:lower:]' || echo unknown)"
count="$(wayle notify list 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ' || echo 0)"
panel="$("$HOME/.config/hypr/scripts/panel-switch.sh" status 2>/dev/null || echo wayle:unknown)"
network="$(nmcli -t -f STATE g 2>/dev/null || echo unknown)"
profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

summary="$(cat <<EOF
Notifications: $count
DND: $dnd
Mode: $notif_mode
Panel: $panel
Network: $network
Power: $profile
Media: $media
GPU: $gpu
EOF
)"

case "$mode" in
  copy)
    if command -v wl-copy >/dev/null 2>&1; then
      printf '%s\n' "$summary" | wl-copy
      command -v notify-send >/dev/null 2>&1 && notify-send -a Noxflow "Status copied" "Notification summary copied to clipboard."
    else
      echo "wl-copy not found" >&2
      exit 1
    fi
    ;;
  popup)
    command -v notify-send >/dev/null 2>&1 && notify-send -a Noxflow "Status Summary" "$summary"
    ;;
  print)
    printf '%s\n' "$summary"
    ;;
  *)
    echo "usage: $0 [print|copy|popup]" >&2
    exit 1
    ;;
esac
