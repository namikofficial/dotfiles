#!/usr/bin/env bash
set -euo pipefail

run_update() {
  if command -v paru >/dev/null 2>&1; then
    paru -Syu
    return
  fi
  if command -v yay >/dev/null 2>&1; then
    yay -Syu
    return
  fi
  sudo pacman -Syu
}

if command -v kitty >/dev/null 2>&1; then
  exec kitty -e sh -lc 'set -euo pipefail; '"$(declare -f run_update)"'; run_update; read -r -p "Press enter to close"'
fi

if command -v foot >/dev/null 2>&1; then
  exec foot -e sh -lc 'set -euo pipefail; '"$(declare -f run_update)"'; run_update; read -r -p "Press enter to close"'
fi

run_update
