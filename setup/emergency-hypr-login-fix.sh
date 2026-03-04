#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

TS="$(date +%F-%H%M%S)"

backup_file() {
  local f="$1"
  if [[ -e "$f" ]]; then
    cp -a "$f" "${f}.bak.${TS}"
  fi
}

echo "[1/7] Disable NVIDIA persistence daemon"
systemctl disable --now nvidia-persistenced.service || true

echo "[2/7] Use conservative NVIDIA module options (hybrid-safe)"
backup_file /etc/modprobe.d/nvidia.conf
cat >/etc/modprobe.d/nvidia.conf <<'EOF'
# Temporary stability setting for hybrid laptops with Hyprland.
options nvidia_drm modeset=0
EOF

backup_file /etc/modprobe.d/nvidia-hybrid.conf
cat >/etc/modprobe.d/nvidia-hybrid.conf <<'EOF'
options nvidia NVreg_DynamicPowerManagement=0x00 NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

echo "[3/7] Disable extra local NVIDIA udev helper rule"
if [[ -f /etc/udev/rules.d/61-nvidia-modprobe.rules ]]; then
  mv /etc/udev/rules.d/61-nvidia-modprobe.rules \
    "/etc/udev/rules.d/61-nvidia-modprobe.rules.disabled.${TS}"
fi

echo "[4/7] Mask upstream 60-nvidia udev rule to avoid GPU probe stalls during boot"
if [[ -e /etc/udev/rules.d/60-nvidia.rules && ! -L /etc/udev/rules.d/60-nvidia.rules ]]; then
  backup_file /etc/udev/rules.d/60-nvidia.rules
fi
ln -sfn /dev/null /etc/udev/rules.d/60-nvidia.rules

echo "[5/7] Force systemd-boot entries to nvidia_drm.modeset=0"
for entry in /boot/loader/entries/*.conf; do
  [[ -f "$entry" ]] || continue
  if grep -Eq 'nvidia[_-]drm\.modeset=' "$entry"; then
    sed -i -E 's/nvidia[_-]drm\.modeset=[01]/nvidia_drm.modeset=0/g' "$entry"
  else
    sed -i -E '/^options\s+/ s|$| nvidia_drm.modeset=0|' "$entry"
  fi
done

echo "[6/7] Reload udev rules and rebuild initramfs"
udevadm control --reload || true
mkinitcpio -P

echo "[7/7] Done"
echo
echo "Reboot now."
echo "After reboot, Hyprland should log in on iGPU reliably."
echo
echo "If you want to re-enable NVIDIA boot probing later:"
echo "  sudo rm -f /etc/udev/rules.d/60-nvidia.rules"
echo "  sudo mv /etc/udev/rules.d/61-nvidia-modprobe.rules.disabled.${TS} /etc/udev/rules.d/61-nvidia-modprobe.rules"
