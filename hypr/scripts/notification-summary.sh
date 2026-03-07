#!/usr/bin/env sh
set -eu

mode="${1:-print}"

media="$("$HOME/.config/waybar/scripts/media.sh" 2>/dev/null || echo '󰐊 idle')"
gpu="$("$HOME/.config/waybar/scripts/gpu.sh" 2>/dev/null || echo '󰢮 n/a')"
dnd="$(swaync-client -sw -D 2>/dev/null || echo false)"
count="$(swaync-client -sw -c 2>/dev/null || echo 0)"
panel="$("$HOME/.config/hypr/scripts/panel-switch.sh" status 2>/dev/null || echo waybar:unknown)"
network="$(nmcli -t -f STATE g 2>/dev/null || echo unknown)"
profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

summary="$(cat <<EOF
Notifications: $count
DND: $dnd
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
      command -v notify-send >/dev/null 2>&1 && notify-send -a SwayNC "Status copied" "Notification summary copied to clipboard."
    else
      echo "wl-copy not found" >&2
      exit 1
    fi
    ;;
  popup)
    command -v notify-send >/dev/null 2>&1 && notify-send -a SwayNC "Status Summary" "$summary"
    ;;
  print)
    printf '%s\n' "$summary"
    ;;
  *)
    echo "usage: $0 [print|copy|popup]" >&2
    exit 1
    ;;
esac
