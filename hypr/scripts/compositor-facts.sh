#!/usr/bin/env bash
set -u

echo "== Hyprland =="
hyprctl version 2>&1

echo
echo "== Active workspace =="
hyprctl -j activeworkspace 2>&1

echo
echo "== Workspaces =="
hyprctl -j workspaces 2>&1

echo
echo "== Monitors =="
hyprctl monitors 2>&1

echo
echo "== Panel =="
"${HOME}/.config/hypr/scripts/panel-switch.sh" status 2>&1 || true

echo
echo "== Packages =="
pacman -Q hyprland hyprutils aquamarine hyprpaper xdg-desktop-portal-hyprland 2>&1
