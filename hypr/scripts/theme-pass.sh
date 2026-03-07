#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Theme Pass" "$1" "${2:-}"
}

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme "Adwaita" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface font-name "Noto Sans 11" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font 11" >/dev/null 2>&1 || true
fi

if command -v kvantummanager >/dev/null 2>&1; then
  kvantummanager --set KvArcDark >/dev/null 2>&1 || true
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

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

if [ -x "$HOME/.config/hypr/scripts/launcher.sh" ]; then
  "$HOME/.config/hypr/scripts/launcher.sh" --rebuild-cache >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
  rm -f "$HOME"/.cache/ksycoca6_* "$HOME"/.cache/ksycoca* >/dev/null 2>&1 || true
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

notify "Theme pass applied" "GTK/Qt + panel + MIME/KDE caches refreshed"
