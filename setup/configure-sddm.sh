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
LOG_FILE="$LOG_DIR/sddm-setup-${TS}.log"
LATEST_LINK="$LOG_DIR/sddm-setup-latest.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== SDDM setup ($(date -u '+%F %T UTC')) ==="
echo "repo: $REPO_DIR"
echo "log:  $LOG_FILE"
echo

if [[ ! -d /usr/share/sddm/themes/elarun ]]; then
  echo "Missing /usr/share/sddm/themes/elarun"
  echo "Install with: sudo pacman -S sddm"
  exit 1
fi

install -Dm644 "$REPO_DIR/sddm/sddm.conf.d/10-noxflow-theme.conf" /etc/sddm.conf.d/10-noxflow-theme.conf
install -Dm644 "$REPO_DIR/sddm/elarun/theme.conf.user" /usr/share/sddm/themes/elarun/theme.conf.user

default_wall="/usr/share/sddm/themes/elarun/elarun.jpg"
target_wall="/usr/share/sddm/themes/elarun/images/noxflow-login.jpg"

src_user="${SUDO_USER:-$USER}"
src_home="$(getent passwd "$src_user" | cut -d: -f6)"
src_wall="${src_home}/.cache/current-wallpaper"
wall_path="$default_wall"

if [[ -f "$src_wall" ]]; then
  wall_path="$(cat "$src_wall" 2>/dev/null || true)"
fi

if [[ ! -f "$wall_path" ]]; then
  wall_path="$default_wall"
fi

mkdir -p "$(dirname "$target_wall")"
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -hide_banner -loglevel error -y -i "$wall_path" \
    -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080" \
    "$target_wall" || cp "$wall_path" "$target_wall"
else
  cp "$wall_path" "$target_wall"
fi

echo "Configured SDDM theme: elarun"
echo "Login background: $target_wall"
echo "Applied config: /etc/sddm.conf.d/10-noxflow-theme.conf"
echo "Applied theme user config: /usr/share/sddm/themes/elarun/theme.conf.user"
echo
echo "Reboot to preview the improved login screen."

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${SUDO_USER}:${SUDO_USER}" "$LOG_FILE" "$LATEST_LINK" 2>/dev/null || true
fi
