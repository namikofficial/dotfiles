#!/usr/bin/env sh
set -eu

if pgrep -af "mpv.*noxflow-screensaver" >/dev/null 2>&1; then
  exit 0
fi

if pgrep -af "screensaver-visual.py" >/dev/null 2>&1; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  exec "$HOME/.config/hypr/scripts/lock.sh"
fi

exec systemd-inhibit \
  --what=idle:sleep:handle-lid-switch \
  --mode=block \
  --who="hyprland" \
  --why="manual visual screensaver while keeping the machine awake" \
  python3 "$HOME/.config/hypr/scripts/screensaver-visual.py"
