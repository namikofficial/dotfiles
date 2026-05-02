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

if stop_if_running "$pid_file"; then
  exit 0
fi

stop_if_running "$other_pid_file" || true

entries=(
  "git commit current project"
  "open noxcrm backend"
  "switch to dev mode"
  "restart portals"
  "run schemathesis"
  "open postgres logs"
  "move current app to workspace 7"
  "create note from clipboard"
  "search browser history"
  "search shell history"
  "kill frozen window"
  "toggle laptop fan monitor"
  "open app launcher"
  "open workspace overview"
  "open notes"
  "open ai helper"
  "open logs stack"
  "open terminal scratchpad"
)

choice="$(
  printf '%s\n' "${entries[@]}" | rofi -dmenu -i \
    -no-show-icons \
    -p 'Command Palette' \
    -mesg 'Desktop actions, project helpers, search, and window control.' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -kb-cancel 'Escape,Control+g,Super+space,Super+a,Super+slash' \
    -format 's' \
    -pid "$pid_file"
)"

rofi_status=$?
rm -f "$pid_file"
[ "$rofi_status" -eq 0 ] || exit 0
[ -n "$choice" ] || exit 0

case "$choice" in
  "git commit current project")
    exec kitty --title "git commit" -e bash -lc 'cd "$HOME/Documents/code/WellVantage" && git status --short && git add -A && git commit'
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
  "move current app to workspace 7")
    exec hyprctl dispatch movetoworkspace 7
    ;;
  "create note from clipboard")
    exec kitty --title "clipboard note" -e bash -lc 'text="$(wl-paste -n 2>/dev/null || true)"; file="$HOME/Documents/notes/clipboard-$(date +%Y%m%d-%H%M%S).md"; printf "# Clipboard Note\n\n%s\n" "$text" > "$file"; command -v code >/dev/null 2>&1 && code "$file" >/dev/null 2>&1 &'
    ;;
  "search browser history")
    exec "$HOME/.config/hypr/scripts/desktop-history-search.sh" browser
    ;;
  "search shell history")
    exec "$HOME/.config/hypr/scripts/desktop-history-search.sh" shell
    ;;
  "kill frozen window")
    exec "$HOME/.config/hypr/scripts/kill-window.sh"
    ;;
  "toggle laptop fan monitor")
    exec "$HOME/.config/hypr/scripts/fan-monitor-toggle.sh"
    ;;
  "open app launcher")
    exec "$HOME/.config/hypr/scripts/launcher.sh" --fast
    ;;
  "open workspace overview")
    exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
    ;;
  "open notes")
    exec "$HOME/.config/hypr/scripts/open-notes.sh"
    ;;
  "open ai helper")
    exec "$HOME/.config/hypr/scripts/ai-helper.sh" menu
    ;;
  "open logs stack")
    exec "$HOME/.config/hypr/scripts/logs-workspace.sh" stack
    ;;
  "open terminal scratchpad")
    exec "$HOME/.config/hypr/scripts/scratchpad-manager.sh" terminal
    ;;
esac
