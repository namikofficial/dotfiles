#!/usr/bin/env sh
set -eu

action="${1:-}"

usage() {
  echo "usage: $0 [up|down]" >&2
}

[ -n "$action" ] || {
  usage
  exit 1
}

if command -v lightctl >/dev/null 2>&1; then
  case "$action" in
    up) lightctl up ;;
    down) lightctl down ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

if command -v swayosd-client >/dev/null 2>&1; then
  case "$action" in
    up) swayosd-client --brightness raise ;;
    down) swayosd-client --brightness lower ;;
    *)
      usage
      exit 1
      ;;
  esac
  exit 0
fi

case "$action" in
  up) brightnessctl -e4 -n2 set 5%+ ;;
  down) brightnessctl -e4 -n2 set 5%- ;;
  *)
    usage
    exit 1
    ;;
esac
