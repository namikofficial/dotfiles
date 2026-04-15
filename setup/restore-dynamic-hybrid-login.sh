#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  cp -a "$path" "${path}.bak.${TS}"
}

echo "[1/7] Remove fragile SDDM VT-switch override"
if [[ -f /etc/systemd/system/sddm.service.d/10-force-greeter-vt.conf ]]; then
  backup_if_exists /etc/systemd/system/sddm.service.d/10-force-greeter-vt.conf
  rm -f /etc/systemd/system/sddm.service.d/10-force-greeter-vt.conf
fi

echo "[2/7] Restore NVIDIA DRM KMS for Wayland"
backup_if_exists /etc/modprobe.d/nvidia.conf
cat >/etc/modprobe.d/nvidia.conf <<'EOF'
# Restored by restore-dynamic-hybrid-login.sh
options nvidia_drm modeset=1 fbdev=1
EOF

echo "[3/7] Re-enable hybrid runtime power management"
backup_if_exists /etc/modprobe.d/nvidia-hybrid.conf
cat >/etc/modprobe.d/nvidia-hybrid.conf <<'EOF'
# Restored by restore-dynamic-hybrid-login.sh
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

echo "[4/7] Unmask NVIDIA udev helper rule if it was disabled"
if [[ -L /etc/udev/rules.d/60-nvidia.rules ]] && [[ "$(readlink -f /etc/udev/rules.d/60-nvidia.rules)" == "/dev/null" ]]; then
  rm -f /etc/udev/rules.d/60-nvidia.rules
fi

echo "[5/7] Ensure boot entries use nvidia_drm.modeset=1"
for entry in /boot/loader/entries/*.conf; do
  [[ -f "$entry" ]] || continue
  backup_if_exists "$entry"
  if grep -Eq 'nvidia[-_]drm\.modeset=' "$entry"; then
    sed -i -E 's/nvidia[-_]drm\.modeset=[01]/nvidia_drm.modeset=1/g' "$entry"
  else
    sed -i -E '/^options\s+/ s|$| nvidia_drm.modeset=1|' "$entry"
  fi
done

echo "[6/7] Reload systemd and rebuild initramfs"
systemctl daemon-reload
udevadm control --reload || true
mkinitcpio -P

echo "[7/7] Done"
echo
echo "Reboot now. SDDM should come up normally without the forced VT handoff."
echo "After login, Hyprland will default to hybrid AQ_DRM_DEVICES ordering."
