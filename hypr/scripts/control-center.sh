#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/quick-actions.sh"

state_dir="$(noxflow_state_dir)"
pid_file="$state_dir/control-center.pid"
mkdir -p "$state_dir"

menu() {
  cat <<'EOF' | rofi -dmenu -i -no-show-icons -p 'Dotfiles Control Center' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -kb-cancel 'Escape,Control+g,Super+space,Super+a,Super+slash'
Health
Health (JSON)
Settings Hub
Settings Doctor
Settings Keycheck
Project Profiles
Project Resume
Launcher
Quick Actions
AI Helper Menu
AI Shell Command
AI Clipboard Summary
Desktop Recovery
EOF
}

if noxflow_stop_if_running "$pid_file"; then
  exit 0
fi

set +e
choice="$(menu)"
status=$?
set -e
[ "$status" -eq 0 ] || exit 0
[ -n "${choice:-}" ] || exit 0

case "$choice" in
  Health) exec kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/dev-health.sh; read -r -p 'Press enter to close'" ;;
  "Health (JSON)") exec kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/dev-health.sh --json; read -r -p 'Press enter to close'" ;;
  "Settings Hub") exec "$SCRIPT_DIR/settings-hub.sh" ;;
  "Settings Doctor") exec kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/hypr/scripts/settingsctl doctor; read -r -p 'Press enter to close'" ;;
  "Settings Keycheck") exec kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/hypr/scripts/settingsctl keycheck; read -r -p 'Press enter to close'" ;;
  "Project Profiles") exec kitty -e /usr/bin/zsh -lic "$HOME/Documents/code/dotfiles/setup/project-profile.sh status; read -r -p 'Press enter to close'" ;;
  "Project Resume") exec "$SCRIPT_DIR/project-resume.sh" ;;
  Launcher) exec "$SCRIPT_DIR/launcher.sh" --fast ;;
  "Quick Actions") exec "$SCRIPT_DIR/quick-actions.sh" ;;
  "AI Helper Menu") exec "$SCRIPT_DIR/ai-helper.sh" menu ;;
  "AI Shell Command") exec "$SCRIPT_DIR/ai-helper.sh" shell ;;
  "AI Clipboard Summary") exec "$SCRIPT_DIR/ai-helper.sh" clip ;;
  "Desktop Recovery") exec "$SCRIPT_DIR/desktop-recovery.sh" menu ;;
esac
