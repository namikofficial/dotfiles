#!/usr/bin/env bash
set -euo pipefail

echo "Restarting portal stack..."

systemctl --user restart xdg-desktop-portal-hyprland.service
systemctl --user restart xdg-desktop-portal.service

echo "Done."
systemctl --user --no-pager --full status \
  xdg-desktop-portal.service \
  xdg-desktop-portal-hyprland.service
