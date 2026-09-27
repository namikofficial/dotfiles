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
  if [[ -L "$dst" ]]; then
    local resolved_dst resolved_src
    resolved_dst="$(readlink -f "$dst" || true)"
    resolved_src="$(readlink -f "$src" || true)"
    if [[ -n "$resolved_dst" && "$resolved_dst" == "$resolved_src" ]]; then
      echo "already linked $dst -> $src"
      return
    fi
  fi
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

force_link "$ROOT_DIR/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
force_link "$ROOT_DIR/hypr/lib" "$HOME/.config/hypr/lib"
force_link "$ROOT_DIR/hypr/monitor-layout.json" "$HOME/.config/hypr/monitor-layout.json"
force_link "$ROOT_DIR/uwsm/env" "$HOME/.config/uwsm/env"
force_link "$ROOT_DIR/wayle/config.toml" "$HOME/.config/wayle/config.toml"
force_link "$ROOT_DIR/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
force_link "$ROOT_DIR/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf" "$HOME/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf"
force_link "$ROOT_DIR/xdg-desktop-portal/hyprland-portals.conf" "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
force_link "$ROOT_DIR/configs/opencode/opencode.local-llamacpp.json" "$HOME/.config/opencode/opencode.json"
force_link "$ROOT_DIR/configs/opencode/cli.json" "$HOME/.config/opencode/cli.json"
force_link "$ROOT_DIR/configs/opencode/plugins/quota-v2" "$HOME/.config/opencode/plugins/quota-v2"
force_link "$ROOT_DIR/configs/opencode/plugins/linux-notify" "$HOME/.config/opencode/plugins/linux-notify"
force_link "$ROOT_DIR/configs/opencode/opencode-quota/quota-toast.json" "$HOME/.config/opencode/opencode-quota/quota-toast.json"
force_link "$HOME/.cache/hypr/theme-colors-rofi.rasi" "$HOME/.config/rofi/theme-colors-rofi.rasi"
force_copy "$ROOT_DIR/mime/mimeapps.list" "$HOME/.config/mimeapps.list"

echo "Normalization complete."
