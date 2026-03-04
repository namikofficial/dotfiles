#!/usr/bin/env bash
set -euo pipefail

echo "=== NVIDIA quick verify ==="
echo

echo "[kernel]"
uname -r
echo

echo "[boot entry]"
if command -v bootctl >/dev/null 2>&1; then
  bootctl status 2>/dev/null | sed -n '1,40p' | rg 'Current Entry|Default Entry|title:|options:' || true
else
  echo "bootctl not available"
fi
echo

echo "[driver package]"
pacman -Q nvidia-open-dkms nvidia-utils nvidia-settings nvidia-prime 2>/dev/null || true
pacman -Q nvidia-dkms nvidia 2>/dev/null || true
echo

echo "[module]"
if modinfo -F license nvidia >/dev/null 2>&1; then
  license="$(modinfo -F license nvidia)"
  echo "nvidia module license: $license"
else
  echo "nvidia module: not found"
fi
lsmod | rg '^nvidia' || true
echo

echo "[runtime]"
nvidia-smi -L 2>/dev/null || echo "nvidia-smi: unable to talk to driver"
echo

echo "[recent kernel warnings]"
journalctl -b -k --no-pager \
  | rg -i 'blocked for more|task .*blocked|nv_drm_dev_load|nvidia-persiste|watchdog did not stop' \
  | tail -n 20 || true
