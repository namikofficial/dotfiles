#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
pid_file="${state_dir}/rofi-actions.pid"
other_pid_file="${state_dir}/rofi-launcher.pid"
mkdir -p "$state_dir"

stop_if_running() {
  local file="$1"
  [ -f "$file" ] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$file"
    return 0
  fi
  rm -f "$file"
  return 1
}

focused_cwd() {
  local pid
  pid="$(hyprctl -j activewindow 2>/dev/null | jq -r '.pid // empty' 2>/dev/null || true)"
  [ -n "$pid" ] || { echo "$HOME"; return 0; }
  readlink "/proc/${pid}/cwd" 2>/dev/null || echo "$HOME"
}

git_root() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo "$1"
}

choose_action() {
  cat <<'EOF' | rofi -dmenu -i -no-show-icons -p 'Command Palette' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -kb-cancel 'Escape,Control+g,Super+space,Super+a,Super+slash' \
    -mesg 'Apps, frequent apps, and context-aware desktop actions.'
Apps
Frequent Apps
Context Actions
Notes / Clipboard
History Search
Window / Focus
Tools / Scratchpads
EOF
}

if stop_if_running "$pid_file"; then
  exit 0
fi
stop_if_running "$other_pid_file" || true

action="$(choose_action || true)"
[ -n "${action:-}" ] || exit 0

cwd="$(focused_cwd)"
root="$(git_root "$cwd")"

case "$action" in
  Apps)
    exec "$HOME/.config/hypr/scripts/launcher.sh" --mode all
    ;;
  "Frequent Apps")
    exec "$HOME/.config/hypr/scripts/launcher.sh"
    ;;
  "Context Actions")
    choice="$(
      cat <<EOF | rofi -dmenu -i -no-show-icons -p 'Context' -theme "$HOME/.config/rofi/actions.rasi"
git commit current project
open noxcrm backend
switch to dev mode
restart portals
run schemathesis
open postgres logs
EOF
    )"
    [ -n "${choice:-}" ] || exit 0
    case "$choice" in
      "git commit current project")
        exec kitty --title "git commit" -e bash -lc "cd '$root' && git status --short && git add -A && git commit"
        ;;
      "open noxcrm backend")
        exec xdg-open "$HOME/Documents/code/noxcrm/workspace/backend"
        ;;
      "switch to dev mode")
        exec "$HOME/.config/hypr/scripts/settingsctl" profile apply performance
        ;;
      "restart portals")
        exec "$HOME/.config/hypr/scripts/restart-portals.sh"
        ;;
      "run schemathesis")
        exec kitty --title "schemathesis" -e bash -lc 'command -v schemathesis >/dev/null 2>&1 && exec schemathesis --help || exec bash'
        ;;
      "open postgres logs")
        exec kitty --title "postgres logs" -e bash -lc 'journalctl -u postgresql -f --no-pager'
        ;;
    esac
    ;;
  "Notes / Clipboard")
    exec "$HOME/.config/hypr/scripts/notes-palette.sh"
    ;;
  "History Search")
    exec "$HOME/.config/hypr/scripts/desktop-history-search.sh"
    ;;
  "Window / Focus")
    choice="$(
      cat <<'EOF' | rofi -dmenu -i -no-show-icons -p 'Window' -theme "$HOME/.config/rofi/actions.rasi"
move current app to workspace 7
open workspace overview
kill frozen window
EOF
    )"
    [ -n "${choice:-}" ] || exit 0
    case "$choice" in
      "move current app to workspace 7") exec hyprctl dispatch movetoworkspace 7 ;;
      "open workspace overview") exec "$HOME/.config/hypr/scripts/workspace-overview.sh" ;;
      "kill frozen window") exec "$HOME/.config/hypr/scripts/kill-window.sh" ;;
    esac
    ;;
  "Tools / Scratchpads")
    exec "$HOME/.config/hypr/scripts/scratchpad-manager.sh" menu
    ;;
esac
