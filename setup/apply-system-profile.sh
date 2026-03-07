#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYS_DIR="$ROOT_DIR/system"
PARTUUID="${1:-}"

if [[ -z "$PARTUUID" ]]; then
  echo "Usage: sudo $0 <root-partuuid>" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup() {
  local p="$1"
  [[ -e "$p" ]] && cp -a "$p" "${p}.bak.${stamp}"
}

install_modprobe_file() {
  local src="$1" dst="$2"
  backup "$dst"
  install -Dm644 "$src" "$dst"
}

install_modprobe_file "$SYS_DIR/etc/modprobe.d/nvidia.conf" /etc/modprobe.d/nvidia.conf
install_modprobe_file "$SYS_DIR/etc/modprobe.d/nvidia-hybrid.conf" /etc/modprobe.d/nvidia-hybrid.conf
install_modprobe_file "$SYS_DIR/etc/modprobe.d/blacklist-nvidia-drm.conf" /etc/modprobe.d/blacklist-nvidia-drm.conf

for template in "$SYS_DIR"/boot/loader/entries/*.conf; do
  name="$(basename "$template")"
  dst="/boot/loader/entries/$name"
  backup "$dst"
  sed "s/REPLACE_PARTUUID/$PARTUUID/g" "$template" > "$dst"
  chmod 644 "$dst"
done

install -Dm644 "$SYS_DIR/etc/systemd/system/noxflow-timeshift-auto.service" /etc/systemd/system/noxflow-timeshift-auto.service
install -Dm644 "$SYS_DIR/etc/systemd/system/noxflow-timeshift-auto.timer" /etc/systemd/system/noxflow-timeshift-auto.timer

systemctl daemon-reload
systemctl enable --now noxflow-timeshift-auto.timer

echo "System profile applied. Rebuild initramfs and reboot recommended."
