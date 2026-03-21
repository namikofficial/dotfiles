#!/usr/bin/env sh
set -eu

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
log_file="${state_dir}/waybar.log"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"
css="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/style.css"
mkdir -p "$state_dir"

pkill -x waybar >/dev/null 2>&1 || true

# Wait briefly so old tray hosts fully disconnect.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x waybar >/dev/null 2>&1 || break
  sleep 0.15
done

start_once() {
  nohup waybar -c "$cfg" -s "$css" >>"$log_file" 2>&1 </dev/null &
}

started=0
for _ in 1 2 3; do
  start_once
  sleep 0.45
  if pgrep -x waybar >/dev/null 2>&1; then
    started=1
    break
  fi
done

if [ "$started" -ne 1 ]; then
  {
    echo "[waybar-restart] failed to start after retries"
    echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
    echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
    echo "HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}"
  } >>"$log_file"
  command -v notify-send >/dev/null 2>&1 && notify-send -a Waybar "Waybar failed to start" "See: $log_file" || true
  exit 1
fi
