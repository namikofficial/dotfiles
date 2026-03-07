#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"

check_link() {
  local target="$1"
  local source="$2"
  if [[ -L "$target" ]]; then
    local t s
    t="$(readlink -f "$target" || true)"
    s="$(readlink -f "$source" || true)"
    if [[ "$t" == "$s" ]]; then
      echo "OK    link $target"
    else
      echo "WARN  wrong link $target -> $t"
    fi
  elif [[ -e "$target" ]]; then
    echo "WARN  copy exists (not symlink): $target"
  else
    echo "WARN  missing target: $target"
  fi
}

check_link "$HOME/.config/hypr/hyprland.conf" "$ROOT_DIR/hypr/hyprland.conf"
check_link "$HOME/.config/swaync" "$ROOT_DIR/hypr/swaync"
check_link "$HOME/.config/waybar" "$ROOT_DIR/hypr/waybar"
check_link "$HOME/.config/rofi" "$ROOT_DIR/hypr/rofi"
check_link "$HOME/.config/kdeglobals" "$ROOT_DIR/kde/kdeglobals"
check_link "$HOME/.config/dolphinrc" "$ROOT_DIR/kde/dolphinrc"
check_link "$HOME/.config/kiorc" "$ROOT_DIR/kde/kiorc"
check_link "$HOME/.config/gwenviewrc" "$ROOT_DIR/kde/gwenviewrc"
check_link "$HOME/.config/mimeapps.list" "$ROOT_DIR/mime/mimeapps.list"

if ! command -v jq >/dev/null 2>&1; then
  echo "WARN  jq is not installed"
fi

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty="$(git -C "$ROOT_DIR" status --short)"
  if [[ -n "$dirty" ]]; then
    echo "WARN  repo has uncommitted changes"
    echo "$dirty"
  else
    echo "OK    repo clean"
  fi
fi

if [[ -f /etc/modprobe.d/nvidia.conf ]]; then
  echo "INFO  system override exists: /etc/modprobe.d/nvidia.conf"
fi
if [[ -f /boot/loader/entries/arch-linux-igpu-safe.conf ]]; then
  echo "INFO  safe boot profile exists: /boot/loader/entries/arch-linux-igpu-safe.conf"
fi

if [[ -f "$ROOT_DIR/settings/state.local.json" ]]; then
  echo "INFO  local settings override present: settings/state.local.json"
else
  echo "INFO  local settings override missing: settings/state.local.json (optional)"
fi
