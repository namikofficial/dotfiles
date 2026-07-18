#!/usr/bin/env bash
set -euo pipefail

action="${1:-play-pause}"

notify_missing() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Media Keys" "playerctl is missing" "Install playerctl from the dotfiles package manifest."
}

case "$action" in
  play-pause | next | previous | pause | play | stop) ;;
  *)
    echo "usage: $0 [play-pause|next|previous|pause|play|stop]" >&2
    exit 2
    ;;
esac

if ! command -v playerctl >/dev/null 2>&1; then
  notify_missing
  exit 127
fi

exec playerctl "$action"
