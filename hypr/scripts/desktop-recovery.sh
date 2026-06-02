#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

action="${1:-menu}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Desktop Recovery" "$1" "${2:-}"
}

run_terminal() {
  local title="$1"
  shift
  exec kitty --title "$title" -e sh -lc "$*; printf '\nPress enter to close'; read -r _"
}

menu() {
  cat <<'MENU' | rofi -dmenu -i -no-show-icons -p 'Recover Desktop' -theme "$HOME/.config/rofi/actions.rasi"
Run dev-health
Restart Wayle panel
Restart portals
Safe Hyprland reload
Reapply theme
Open desktop logs
Open settings doctor
Show project profiles
MENU
}

if [ "$action" = "menu" ]; then
  choice="$(menu || true)"
  [ -n "${choice:-}" ] || exit 0
  case "$choice" in
    "Run dev-health") action="dev-health" ;;
    "Restart Wayle panel") action="wayle" ;;
    "Restart portals") action="portals" ;;
    "Safe Hyprland reload") action="hypr" ;;
    "Reapply theme") action="theme" ;;
    "Open desktop logs") action="logs" ;;
    "Open settings doctor") action="doctor" ;;
    "Show project profiles") action="projects" ;;
  esac
fi

case "$action" in
  dev-health)
    run_terminal "dev-health" "$REPO_DIR/setup/dev-health.sh"
    ;;
  wayle)
    "$SCRIPT_DIR/panel-switch.sh" show
    notify "Wayle panel restored"
    ;;
  portals)
    exec "$SCRIPT_DIR/restart-portals.sh"
    ;;
  hypr)
    exec "$SCRIPT_DIR/hypr-reload-safe.sh"
    ;;
  theme)
    exec "$SCRIPT_DIR/theme-pass.sh"
    ;;
  logs)
    exec "$SCRIPT_DIR/logs-workspace.sh" stack
    ;;
  doctor)
    run_terminal "settings doctor" "$SCRIPT_DIR/settings/doctor.sh"
    ;;
  projects)
    run_terminal "project profiles" "$REPO_DIR/setup/project-profile.sh status"
    ;;
  *)
    echo "unknown recovery action: $action" >&2
    exit 2
    ;;
esac
