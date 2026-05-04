#!/usr/bin/env bash
set -euo pipefail

packages=(
  hyprpanel
  eww
  dunst
  wofi
  awww
)

installed=()
for pkg in "${packages[@]}"; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then
    installed+=("$pkg")
  fi
done

if ((${#installed[@]} == 0)); then
  echo "No legacy shell packages are installed."
  exit 0
fi

echo "Removing legacy shell packages: ${installed[*]}"
sudo pacman -Rns "${installed[@]}"
