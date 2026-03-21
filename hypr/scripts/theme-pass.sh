#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Reload" "$1" "${2:-}"
}

finish_slow_refresh() {
  if [ -x "$HOME/.config/hypr/scripts/launcher.sh" ]; then
    "$HOME/.config/hypr/scripts/launcher.sh" --rebuild-cache >/dev/null 2>&1 || true
  fi

  rm -f "$HOME/.local/share/applications/mimeinfo.cache" >/dev/null 2>&1 || true

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi

  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    rm -f "$HOME"/.cache/ksycoca6_* "$HOME"/.cache/ksycoca* >/dev/null 2>&1 || true
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  fi
}

notify "Reloading..." "Applying theme and refreshing running apps"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Ice" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface font-name "Noto Sans 11" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font 11" >/dev/null 2>&1 || true
fi

if command -v kvantummanager >/dev/null 2>&1; then
  kvantummanager --set NoxflowDynamic >/dev/null 2>&1 || true
fi

kitty_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

kitty_remote_all() {
  command -v kitty >/dev/null 2>&1 || return 0
  for sock in "$kitty_runtime_dir"/kitty-control*; do
    [ -S "$sock" ] || continue
    kitty @ --to "unix:$sock" "$@" >/dev/null 2>&1 || true
  done
}

current_wall=""
if [ -f "$HOME/.cache/current-wallpaper" ]; then
  current_wall="$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null || true)"
fi

if [ -n "$current_wall" ] && [ -f "$current_wall" ]; then
  if [ -x "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" ]; then
    "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" "$current_wall" >/dev/null 2>&1 || true
  fi
  if [ -x "$HOME/.config/hypr/scripts/theme-sync.sh" ]; then
    "$HOME/.config/hypr/scripts/theme-sync.sh" "$current_wall" >/dev/null 2>&1 || true
  fi
fi



if [ -x "$HOME/.config/hypr/scripts/restart-waybar.sh" ]; then
  "$HOME/.config/hypr/scripts/restart-waybar.sh" >/dev/null 2>&1 || true
fi

if command -v swaync-client >/dev/null 2>&1; then
  swaync-client -rs >/dev/null 2>&1 || true
fi

if command -v eww >/dev/null 2>&1 && [ -d "$HOME/.config/eww" ]; then
  eww --config "$HOME/.config/eww" reload >/dev/null 2>&1 || true
fi

kitty_remote_all load-config "$HOME/.config/kitty/kitty.conf"

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

notify "Reload complete" "Theme + Kitty + Hyprland + panel + desktop caches refreshed"

finish_slow_refresh >/dev/null 2>&1 &
