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

THEME_NAME="noxflow"
THEME_SRC="$REPO_DIR/sddm/$THEME_NAME"
THEME_DEST="/usr/share/sddm/themes/$THEME_NAME"

if [[ ! -d "$THEME_SRC" ]]; then
  echo "Missing theme source in repo: $THEME_SRC"
  exit 1
fi

if [[ ! -d /usr/share/sddm/themes ]]; then
  echo "Missing /usr/share/sddm/themes"
  echo "Install/enable SDDM first."
  exit 1
fi

install -Dm644 "$REPO_DIR/sddm/sddm.conf.d/10-noxflow-theme.conf" /etc/sddm.conf.d/10-noxflow-theme.conf

rm -rf "$THEME_DEST"
mkdir -p "$THEME_DEST"
cp -r "$THEME_SRC"/. "$THEME_DEST"/
chown -R root:root "$THEME_DEST"
chmod -R a+rX "$THEME_DEST"

default_wall="$THEME_DEST/images/background.png"
target_wall="$THEME_DEST/images/noxflow-login.jpg"

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

echo "Configured SDDM theme: $THEME_NAME"
echo "Login background: $target_wall"
echo "Applied config: /etc/sddm.conf.d/10-noxflow-theme.conf"
echo "Installed theme: $THEME_DEST"
echo
echo "Reboot to preview the improved login screen."

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${SUDO_USER}:${SUDO_USER}" "$LOG_FILE" "$LATEST_LINK" 2>/dev/null || true
fi
