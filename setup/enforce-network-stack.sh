#!/usr/bin/env bash
set -euo pipefail

# Enforce the workstation Wi-Fi standard:
# NetworkManager + wpa_supplicant backend, with iwd disabled.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

echo "==> Enforcing NetworkManager + wpa_supplicant policy"

if ! pacman -Q networkmanager >/dev/null 2>&1 || ! pacman -Q wpa_supplicant >/dev/null 2>&1; then
  echo "==> Installing required packages: networkmanager, wpa_supplicant"
  as_root pacman -S --needed networkmanager wpa_supplicant
fi

if pacman -Q iwd >/dev/null 2>&1; then
  echo "==> Removing conflicting package: iwd"
  as_root pacman -Rns --noconfirm iwd
fi

echo "==> Masking iwd service to prevent accidental enable"
as_root systemctl mask iwd.service || true

echo "==> Pinning NetworkManager backend to wpa_supplicant"
as_root mkdir -p /etc/NetworkManager/conf.d
cat <<'EOF' | as_root tee /etc/NetworkManager/conf.d/20-wifi-backend.conf >/dev/null
[device]
wifi.backend=wpa_supplicant
EOF
as_root rm -f /etc/NetworkManager/conf.d/10-iwd.conf

echo "==> Restarting network services"
as_root systemctl enable --now NetworkManager.service
as_root systemctl restart NetworkManager.service

echo
echo "==> Verification"
systemctl list-units --type=service | grep -E "NetworkManager|wpa_supplicant|iwd" || true
echo
if command -v iw >/dev/null 2>&1; then
  iw dev | sed -n '1,80p'
fi
