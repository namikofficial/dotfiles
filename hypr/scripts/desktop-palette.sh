#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

state_dir="$(noxflow_state_dir)"
pid_file="$state_dir/rofi-actions.pid"
other_pid_file="$state_dir/rofi-launcher.pid"
mkdir -p "$state_dir"

choose_action() {
  cat <<'EOF' | rofi -dmenu -i -no-show-icons -p 'Command Palette' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -kb-cancel 'Escape,Control+g,Super+space,Super+a,Super+slash' \
    -mesg 'Apps, frequent apps, and context-aware desktop actions.'
Apps
Frequent Apps
Context Actions
Control Center
Notes / Clipboard
History Search
Window / Focus
Tools / Scratchpads
EOF
}

if noxflow_stop_if_running "$pid_file"; then
  exit 0
fi
noxflow_stop_if_running "$other_pid_file" || true

action="$(choose_action || true)"
[ -n "${action:-}" ] || exit 0

cwd="$(noxflow_focused_cwd)"
root="$(noxflow_git_root "$cwd")"

case "$action" in
  Apps)
    exec "$HOME/.config/hypr/scripts/launcher.sh" --fast
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
recover desktop
run dev health
project profiles
run schemathesis
open postgres logs
EOF
    )"
    [ -n "${choice:-}" ] || exit 0
    case "$choice" in
      "git commit current project")
        exec kitty --title "git commit" -e /usr/bin/zsh -lic "cd '$root' && git status --short && git add -A && git commit"
        ;;
      "open noxcrm backend")
        exec xdg-open "$HOME/Documents/code/noxorigin/workspace/backend"
        ;;
      "switch to dev mode")
        exec "$HOME/.config/hypr/scripts/settingsctl" profile apply performance
        ;;
      "restart portals")
        exec "$HOME/.config/hypr/scripts/restart-portals.sh"
        ;;
      "recover desktop")
        exec "$HOME/.config/hypr/scripts/desktop-recovery.sh" menu
        ;;
      "run dev health")
        exec kitty --title "dev-health" -e /usr/bin/zsh -lic "cd '$HOME/Documents/code/dotfiles' && setup/dev-health.sh; read -r -p 'Press enter to close'"
        ;;
      "project profiles")
        exec kitty --title "project profiles" -e /usr/bin/zsh -lic "cd '$HOME/Documents/code/dotfiles' && setup/project-profile.sh status; read -r -p 'Press enter to close'"
        ;;
      "run schemathesis")
        exec kitty --title "schemathesis" -e /usr/bin/zsh -lic 'command -v schemathesis >/dev/null 2>&1 && exec schemathesis --help || exec zsh -l'
        ;;
      "open postgres logs")
        exec kitty --title "postgres logs" -e /usr/bin/zsh -lic 'journalctl -u postgresql -f --no-pager'
        ;;
    esac
    ;;
  "Control Center")
    exec "$HOME/.config/hypr/scripts/control-center.sh"
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
