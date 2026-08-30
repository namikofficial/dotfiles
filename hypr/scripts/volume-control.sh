#!/usr/bin/env sh
# Volume control — direct PipeWire via wpctl.
# NoxFlow island provides the visual OSD; this script only changes audio state.
set -eu

action="${1:-}"

usage() {
  echo "usage: $0 [up|down|mute|mic-mute]" >&2
}

[ -n "$action" ] || {
  usage
  exit 1
}

case "$action" in
  up) wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ ;;
  down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
  mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
  mic-mute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
  *)
    usage
    exit 1
    ;;
esac
