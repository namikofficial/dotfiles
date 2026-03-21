#!/usr/bin/env sh
set -eu

state_base="${XDG_RUNTIME_DIR:-/tmp}"
state_dir="$state_base/noxflow"
pid_file="$state_dir/keep-awake.pid"
mode="${1:-keep-awake}"

if ! mkdir -p "$state_dir" 2>/dev/null; then
  state_dir="/tmp/noxflow"
  pid_file="$state_dir/keep-awake.pid"
  mkdir -p "$state_dir"
fi

if [ -f "$pid_file" ]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
    rm -f "$pid_file"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -a "Noxflow" "Keep-awake disabled" >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  rm -f "$pid_file"
fi

if [ "$mode" = "--visual" ] || [ "$mode" = "visual" ]; then
  if pgrep -af "screensaver-visual.py" >/dev/null 2>&1; then
    exit 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    exec "$HOME/.config/hypr/scripts/lock.sh"
  fi
  if [ -r /usr/lib/liblayer-shell-preload.so ]; then
    case "${LD_PRELOAD:-}" in
      *liblayer-shell-preload.so*) ;;
      "") export LD_PRELOAD="/usr/lib/liblayer-shell-preload.so" ;;
      *) export LD_PRELOAD="/usr/lib/liblayer-shell-preload.so:${LD_PRELOAD}" ;;
    esac
  fi
  exec systemd-inhibit \
    --what=idle:sleep:handle-lid-switch \
    --mode=block \
    --who="hyprland" \
    --why="manual visual screensaver while keeping the machine awake" \
    python3 "$HOME/.config/hypr/scripts/screensaver-visual.py"
fi

if command -v systemd-inhibit >/dev/null 2>&1; then
  systemd-inhibit \
    --what=idle:sleep:handle-lid-switch \
    --mode=block \
    --who="hyprland" \
    --why="manual keep-awake mode (no visual rendering)" \
    sh -c 'while :; do sleep 3600; done' >/dev/null 2>&1 &
  new_pid="$!"
  sleep 0.1
  if ! kill -0 "$new_pid" 2>/dev/null; then
    sh -c 'while :; do sleep 3600; done' >/dev/null 2>&1 &
    new_pid="$!"
  fi
else
  sh -c 'while :; do sleep 3600; done' >/dev/null 2>&1 &
  new_pid="$!"
fi

printf '%s\n' "$new_pid" > "$pid_file"
command -v notify-send >/dev/null 2>&1 && \
  notify-send -a "Noxflow" "Keep-awake enabled (low-power mode)" >/dev/null 2>&1 || true
