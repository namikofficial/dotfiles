#!/usr/bin/env bash
set -euo pipefail

echo "Restarting PipeWire + portal stack..."

systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service
systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service

echo "Done."
systemctl --user --no-pager --full status \
  pipewire.service \
  pipewire-pulse.service \
  wireplumber.service \
  xdg-desktop-portal.service \
  xdg-desktop-portal-hyprland.service
