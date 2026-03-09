#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    mv "$p" "${p}.bak.${STAMP}"
  fi
}

force_link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  ln -s "$src" "$dst"
  echo "link $dst -> $src"
}

force_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  cp -a "$src" "$dst"
  echo "copy $dst <- $src"
}

force_link "$ROOT_DIR/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
force_link "$ROOT_DIR/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
force_link "$ROOT_DIR/theme/qt5ct/qt5ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"
force_link "$ROOT_DIR/theme/qt6ct/qt6ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"
force_copy "$ROOT_DIR/kde/kdeglobals" "$HOME/.config/kdeglobals"
force_link "$ROOT_DIR/kde/dolphinrc" "$HOME/.config/dolphinrc"
force_link "$ROOT_DIR/kde/kiorc" "$HOME/.config/kiorc"
force_link "$ROOT_DIR/kde/gwenviewrc" "$HOME/.config/gwenviewrc"
force_copy "$ROOT_DIR/mime/mimeapps.list" "$HOME/.config/mimeapps.list"
force_copy "$ROOT_DIR/theme/Kvantum" "$HOME/.config/Kvantum"

echo "Normalization complete."
