#!/usr/bin/env bash
set -euo pipefail

# Enforce the workstation Wi-Fi standard:
# NetworkManager + wpa_supplicant backend, with iwd disabled.

DRY_RUN=0
AUTO_YES=0

usage() {
  cat <<'EOF'
usage: enforce-network-stack.sh [--dry-run] [--yes]

  --dry-run  Show the actions without changing the system.
  --yes      Apply the destructive changes without prompting.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) AUTO_YES=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

run_root() {
  if (( DRY_RUN )); then
    printf '[dry-run] sudo %s\n' "$*"
  else
    as_root "$@"
  fi
}

confirm() {
  if (( DRY_RUN || AUTO_YES )); then
    return 0
  fi
  printf 'This will remove iwd if installed and restart NetworkManager. Continue? [y/N] '
  read -r answer
  case "${answer:-N}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
}

echo "==> Enforcing NetworkManager + wpa_supplicant policy"
confirm

if ! pacman -Q networkmanager >/dev/null 2>&1 || ! pacman -Q wpa_supplicant >/dev/null 2>&1; then
  echo "==> Installing required packages: networkmanager, wpa_supplicant"
  run_root pacman -S --needed networkmanager wpa_supplicant
fi

if pacman -Q iwd >/dev/null 2>&1; then
  echo "==> Removing conflicting package: iwd"
  run_root pacman -Rns --noconfirm iwd
fi

echo "==> Masking iwd service to prevent accidental enable"
run_root systemctl mask iwd.service || true

echo "==> Pinning NetworkManager backend to wpa_supplicant"
run_root mkdir -p /etc/NetworkManager/conf.d
if (( DRY_RUN )); then
  cat <<'EOF'
[dry-run] write /etc/NetworkManager/conf.d/20-wifi-backend.conf
[device]
wifi.backend=wpa_supplicant
EOF
else
cat <<'EOF' | as_root tee /etc/NetworkManager/conf.d/20-wifi-backend.conf >/dev/null
[device]
wifi.backend=wpa_supplicant
EOF
fi
run_root rm -f /etc/NetworkManager/conf.d/10-iwd.conf

echo "==> Restarting network services"
run_root systemctl enable --now NetworkManager.service
run_root systemctl restart NetworkManager.service

if (( DRY_RUN )); then
  echo
  echo "==> Dry run complete"
  exit 0
fi

echo
echo "==> Verification"
systemctl list-units --type=service | grep -E "NetworkManager|wpa_supplicant|iwd" || true
echo
if command -v iw >/dev/null 2>&1; then
  iw dev | sed -n '1,80p'
fi
