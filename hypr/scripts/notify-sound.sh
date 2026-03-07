#!/usr/bin/env sh
set -eu

kind="${1:-default}"

if ! command -v canberra-gtk-play >/dev/null 2>&1; then
  exit 0
fi

play_id() {
  canberra-gtk-play -i "$1" -d swaync >/dev/null 2>&1 || true
}

case "$kind" in
  critical)
    play_id dialog-warning
    ;;
  message)
    play_id message-new-instant
    ;;
  system)
    play_id service-login
    ;;
  *)
    play_id message
    ;;
esac
