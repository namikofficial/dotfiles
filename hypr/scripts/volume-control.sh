#!/usr/bin/env sh
set -eu

action="${1:-}"

usage() {
  echo "usage: $0 [up|down|mute|mic-mute]" >&2
}

[ -n "$action" ] || {
  usage
  exit 1
}

if command -v volumectl >/dev/null 2>&1; then
  case "$action" in
    up) volumectl -u up ;;
    down) volumectl down ;;
    mute) volumectl toggle-mute ;;
    mic-mute) volumectl -m toggle-mute ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

if command -v swayosd-client >/dev/null 2>&1; then
  case "$action" in
    up) swayosd-client --output-volume raise ;;
    down) swayosd-client --output-volume lower ;;
    mute) swayosd-client --output-volume mute-toggle ;;
    mic-mute) swayosd-client --input-volume mute-toggle ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

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
