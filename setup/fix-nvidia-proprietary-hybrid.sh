#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo "[1/7] Disable nvidia-persistenced (can deadlock on some hybrid setups)"
systemctl disable --now nvidia-persistenced.service || true

echo "[2/7] Select NVIDIA kernel-module package"
DRIVER_PKG=""
if pacman -Si nvidia-dkms >/dev/null 2>&1; then
  DRIVER_PKG="nvidia-dkms"
  for pkg in nvidia-open-dkms nvidia-open; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
      pacman -Rns --noconfirm "$pkg"
    fi
  done
else
  DRIVER_PKG="nvidia-open-dkms"
  echo "note: nvidia-dkms is not available in current repos; using $DRIVER_PKG"
fi

echo "[3/7] Install NVIDIA userspace + module stack"
pacman -S --needed --noconfirm \
  linux-headers \
  "$DRIVER_PKG" \
  nvidia-utils \
  lib32-nvidia-utils \
  nvidia-settings \
  nvidia-prime \
  egl-wayland

echo "[4/7] Write hybrid Wayland module options"
if [ -f /etc/modprobe.d/nvidia.conf ]; then
  ts="$(date +%F-%H%M%S)"
  cp /etc/modprobe.d/nvidia.conf "/etc/modprobe.d/nvidia.conf.bak.${ts}"
fi
cat >/etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
EOF

if [ -f /etc/modprobe.d/nvidia-hybrid.conf ]; then
  ts="$(date +%F-%H%M%S)"
  cp /etc/modprobe.d/nvidia-hybrid.conf "/etc/modprobe.d/nvidia-hybrid.conf.bak.${ts}"
fi
cat >/etc/modprobe.d/nvidia-hybrid.conf <<'EOF'
# Hybrid Wayland defaults with runtime power management enabled.
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

cat >/etc/modprobe.d/blacklist-nvidia-drm.conf <<'EOF'
# Keep empty so NVIDIA DRM stays available for Wayland sessions/greeters.
EOF

echo "[5/7] Ensure NVIDIA DRM modeset is enabled in systemd-boot entries"
for entry in /boot/loader/entries/*.conf; do
  [[ -f "$entry" ]] || continue
  if grep -Eq 'nvidia[-_]drm\.modeset=' "$entry"; then
    sed -i -E 's/nvidia[-_]drm\.modeset=[01]/nvidia_drm.modeset=1/g' "$entry"
  else
    sed -i -E '/^options\s+/ s|$| nvidia_drm.modeset=1|' "$entry"
  fi
done

echo "[6/7] Rebuild initramfs"
mkinitcpio -P

echo "[7/7] Done"
echo "Reboot now, then test:"
echo "  nvidia-smi"
echo "  vulkaninfo | head -n 20"
echo "  journalctl -b -p 0..3 --no-pager | rg -i 'nvidia|hung|blocked'"
