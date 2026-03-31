#!/usr/bin/env sh
set -eu

mode="${1:-start}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ipc="$script_dir/cliphist-ipc.py"
ui="$script_dir/cliphist-ui.py"

is_ready() {
  python3 "$ipc" ping >/dev/null 2>&1
}

start_daemon() {
  python3 "$ui" --daemon >/dev/null 2>&1 &
}

case "$mode" in
  start|ensure)
    if is_ready; then
      exit 0
    fi
    start_daemon
    i=0
    while [ "$i" -lt 40 ]; do
      if is_ready; then
        exit 0
      fi
      i=$((i + 1))
      sleep 0.05
    done
    exit 1
    ;;
  stop)
    python3 "$ipc" quit >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: $0 [start|ensure|stop]" >&2
    exit 1
    ;;
esac
