#!/usr/bin/env sh
set -eu

cfg="$HOME/.config/eww"
err_file="${XDG_RUNTIME_DIR:-/tmp}/eww-desktop-toggle.err"
left_id="desktop-left"
right_id="desktop-right"
left_open="desktoppanel:${left_id}"
right_open="desktoppanel_right:${right_id}"
action="${1:-toggle}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Widgets "$1" "${2:-}"
}

run_eww() {
  tries=0
  while [ "$tries" -lt 5 ]; do
    if eww --config "$cfg" "$@" 2>"$err_file"; then
      return 0
    fi
    if grep -qi "Resource temporarily unavailable" "$err_file" 2>/dev/null; then
      tries=$((tries + 1))
      sleep 0.2
      continue
    fi
    return 1
  done
  return 1
}

ensure_eww() {
  if ! run_eww ping >/dev/null; then
    eww --config "$cfg" daemon >/dev/null 2>&1 &
    sleep 1
  fi

  if ! run_eww ping >/dev/null; then
    notify "Eww daemon unavailable" "Unable to start desktop widgets."
    exit 1
  fi
}

is_open() {
  run_eww active-windows 2>/dev/null | grep -q "^${left_id}:"
}

open_widgets() {
  run_eww open-many "$left_open" "$right_open"
}

close_widgets() {
  run_eww close "$left_id" >/dev/null 2>&1 || true
  run_eww close "$right_id" >/dev/null 2>&1 || true
  run_eww close desktoppanel >/dev/null 2>&1 || true
  run_eww close desktoppanel_right >/dev/null 2>&1 || true
}

if ! command -v eww >/dev/null 2>&1; then
  notify "eww is not installed" "Install with: yay -S eww"
  exit 1
fi

if [ ! -f "$cfg/eww.yuck" ]; then
  notify "eww config missing" "$cfg/eww.yuck not found"
  exit 1
fi

ensure_eww

case "$action" in
  toggle)
    if is_open; then
      close_widgets
      notify "Desktop widgets" "Hidden"
    else
      open_widgets
      notify "Desktop widgets" "Shown"
    fi
    ;;
  show)
    if ! is_open; then
      open_widgets
    fi
    ;;
  hide)
    close_widgets
    ;;
  status)
    if is_open; then
      echo "shown"
    else
      echo "hidden"
    fi
    ;;
  *)
    echo "usage: $0 [toggle|show|hide|status]" >&2
    exit 1
    ;;
esac
