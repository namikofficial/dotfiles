#!/usr/bin/env sh
set -eu

mode="${1:-start}"

is_ready() {
  systemctl --user is-active author-clipboard-daemon >/dev/null 2>&1
}

start_daemon() {
  systemctl --user start author-clipboard-daemon
}

case "$mode" in
  start | ensure)
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
    systemctl --user stop author-clipboard-daemon
    ;;
  restart)
    systemctl --user restart author-clipboard-daemon
    ;;
  status)
    systemctl --user status author-clipboard-daemon
    ;;
  *)
    echo "usage: $0 [start|ensure|stop|restart|status]" >&2
    exit 1
    ;;
esac
