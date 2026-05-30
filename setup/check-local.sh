#!/usr/bin/env bash
# Run all local dotfiles checks before pushing or rebooting.
# Requires: shellcheck, shfmt (in pacman-packages.txt)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section() {
  printf '\n\033[1;34m== %s ==\033[0m\n' "$1"
}

section "shell scripts (shellcheck + shfmt)"
"$SCRIPT_DIR/check-shell.sh" --all

section "stale references"
"$SCRIPT_DIR/check-stale-references.sh"

section "hyprland config syntax"
if command -v Hyprland >/dev/null 2>&1; then
  Hyprland --verify-config -c "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
else
  echo "Hyprland not in PATH, skipping config verify"
fi

printf '\n\033[1;32mOK\033[0m\n'
