#!/usr/bin/env bash
set -u

out="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-screen-share-debug-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$out")"

{
  echo "== Kernel =="
  uname -a

  echo
  echo "== Hyprland version =="
  hyprctl version 2>&1

  echo
  echo "== Hyprland monitors =="
  hyprctl monitors 2>&1

  echo
  echo "== Active workspace =="
  hyprctl -j activeworkspace 2>&1

  echo
  echo "== Workspaces =="
  hyprctl -j workspaces 2>&1

  echo
  echo "== Packages =="
  pacman -Q \
    hyprland \
    hyprutils \
    aquamarine \
    hyprpaper \
    xdg-desktop-portal \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    wireplumber 2>&1

  echo
  echo "== Portal config =="
  for f in \
    "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf" \
    /usr/share/xdg-desktop-portal/hyprland-portals.conf \
    /usr/share/xdg-desktop-portal/gtk-portals.conf \
    /usr/share/xdg-desktop-portal/kde-portals.conf; do
    [ -f "$f" ] || continue
    echo "--- $f"
    sed -n '1,120p' "$f"
  done

  echo
  echo "== User services =="
  systemctl --user status \
    xdg-desktop-portal \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    pipewire \
    pipewire-pulse \
    wireplumber --no-pager 2>&1

  echo
  echo "== Portal logs =="
  journalctl --user \
    -u xdg-desktop-portal \
    -u xdg-desktop-portal-hyprland \
    -u xdg-desktop-portal-gtk \
    --since "30 minutes ago" --no-pager 2>&1

  echo
  echo "== PipeWire/WirePlumber logs =="
  journalctl --user -u pipewire -u pipewire-pulse -u wireplumber --since "30 minutes ago" --no-pager 2>&1

  echo
  echo "== wpctl status =="
  wpctl status 2>&1

  echo
  echo "== pactl info =="
  pactl info 2>&1
} > "$out"

echo "Debug log written to: $out"
