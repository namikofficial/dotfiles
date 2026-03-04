#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/pre-reboot-${TS}.log"
LATEST_LINK="$LOG_DIR/pre-reboot-latest.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Pre-reboot apply ($(date -u +%F' '%T' UTC')) ==="
echo "repo: $REPO_DIR"
echo "log:  $LOG_FILE"
echo

echo "[1/4] Normalize boot args for hybrid NVIDIA stability"
"$SCRIPT_DIR/fix-systemd-boot-nvidia.sh"
echo

echo "[2/4] Set default boot entry to normal Arch profile (not iGPU-safe)"
target_entry="$(grep -l -E '^title[[:space:]]+Arch Linux \(linux\)$' /boot/loader/entries/*.conf | head -n1 || true)"
if [[ -n "$target_entry" ]]; then
  bootctl set-default "$(basename "$target_entry")"
  echo "default set to: $(basename "$target_entry")"
else
  echo "warning: could not find 'Arch Linux (linux)' entry; leaving default unchanged"
fi
echo

echo "[3/4] Ensure helper packages"
pacman -S --needed nwg-dock-hyprland wev
echo

echo "[4/4] Snapshot status"
bootctl status 2>/dev/null | rg 'Current Entry|Default Entry' || true
sed -n '1,40p' /boot/loader/entries/*.conf | rg 'title|options|^==' || true
echo

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"

if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${SUDO_USER}:${SUDO_USER}" "$LOG_FILE" "$LATEST_LINK" 2>/dev/null || true
fi

echo "Done."
echo "Latest log: $LATEST_LINK"
echo "Next: reboot, then run ./setup/post-reboot-verify.sh"
