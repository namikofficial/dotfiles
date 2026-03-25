#!/usr/bin/env bash
set -euo pipefail

if [ -x "$HOME/.config/hypr/scripts/logs-workspace.sh" ]; then
  "$HOME/.config/hypr/scripts/logs-workspace.sh" open
  exit 0
fi

if command -v kitty >/dev/null 2>&1; then
  kitty -e sh -lc 'cd "$HOME/Documents/code/dotfiles/logs" && ls -lah && echo && read -r -p "Press enter to close"'
fi
