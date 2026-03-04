#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

TS="$(date +%F-%H%M%S)"

backup_file() {
  local f="$1"
  [[ -e "$f" ]] && cp -a "$f" "${f}.bak.${TS}"
}

echo "[1/6] Disable NVIDIA persistence daemon"
systemctl disable --now nvidia-persistenced.service || true

echo "[2/6] Blacklist NVIDIA modules for stable iGPU-only boot"
backup_file /etc/modprobe.d/blacklist-nvidia-local.conf
cat >/etc/modprobe.d/blacklist-nvidia-local.conf <<'EOF'
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF

backup_file /etc/modprobe.d/nvidia.conf
cat >/etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=0
EOF

echo "[3/6] Ensure iGPU-safe boot entry is correct"
SAFE_ENTRY="/boot/loader/entries/arch-linux-igpu-safe.conf"
if [[ ! -f "$SAFE_ENTRY" ]]; then
  echo "ERROR: missing $SAFE_ENTRY"
  exit 1
fi

backup_file "$SAFE_ENTRY"
sed -i -E \
  's#modprobe\.blacklist=[^ ]*#modprobe.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm#g' \
  "$SAFE_ENTRY"
if grep -Eq 'nvidia[_-]drm\.modeset=' "$SAFE_ENTRY"; then
  sed -i -E 's/nvidia[_-]drm\.modeset=[01]/nvidia_drm.modeset=0/g' "$SAFE_ENTRY"
else
  sed -i -E '/^options\s+/ s|$| nvidia_drm.modeset=0|' "$SAFE_ENTRY"
fi

echo "[4/6] Set systemd-boot default to iGPU-safe entry"
if command -v bootctl >/dev/null 2>&1; then
  bootctl set-default arch-linux-igpu-safe.conf
else
  backup_file /boot/loader/loader.conf
  if grep -q '^default ' /boot/loader/loader.conf; then
    sed -i -E 's#^default .*#default arch-linux-igpu-safe.conf#' /boot/loader/loader.conf
  else
    printf 'default arch-linux-igpu-safe.conf\n' >>/boot/loader/loader.conf
  fi
fi

echo "[5/6] Rebuild initramfs"
mkinitcpio -P

echo "[6/6] Done"
echo
echo "Use the magic-sysrq reboot to avoid shutdown hangs on this broken boot:"
echo "  sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo s > /proc/sysrq-trigger; echo u > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger'"
