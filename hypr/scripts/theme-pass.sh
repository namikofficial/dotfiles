#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Theme Pass" "$1" "${2:-}"
}

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme "Adwaita" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface font-name "Noto Sans 11" >/dev/null 2>&1 || true
fi

if command -v kvantummanager >/dev/null 2>&1; then
  kvantummanager --set KvArcDark >/dev/null 2>&1 || true
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

notify "Theme pass applied" "GTK + Qt + Kvantum synced"
