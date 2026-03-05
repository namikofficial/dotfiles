#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_LIST="$SCRIPT_DIR/flatpak-apps.txt"
DRY_RUN=0
SYSTEM_INSTALL=0

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --system) SYSTEM_INSTALL=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: install-flatpak-apps.sh [--system] [--dry-run]
  --system   Install apps to system scope
  --dry-run  Print actions only
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if ! command -v flatpak >/dev/null 2>&1; then
  echo "flatpak is required. Install it first with pacman."
  exit 1
fi

read_apps() {
  grep -E -v '^\s*($|#)' "$APP_LIST"
}

scope_flag="--user"
if (( SYSTEM_INSTALL )); then
  scope_flag="--system"
fi

run() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

if ! flatpak remote-list | awk '{print $1}' | grep -qx flathub; then
  run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

while IFS= read -r app; do
  [ -n "$app" ] || continue
  run flatpak install -y "$scope_flag" flathub "$app"
done < <(read_apps)
