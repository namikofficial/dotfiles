#!/usr/bin/env sh
set -eu

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
log_file="${state_dir}/waybar.log"
mkdir -p "$state_dir"

pkill -x waybar >/dev/null 2>&1 || true

# Wait briefly so old tray hosts fully disconnect.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x waybar >/dev/null 2>&1 || break
  sleep 0.15
done

waybar >>"$log_file" 2>&1 &
