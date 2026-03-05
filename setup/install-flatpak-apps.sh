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

all_installed=1
while IFS= read -r app; do
  [ -n "$app" ] || continue
  if ! flatpak info "$app" >/dev/null 2>&1; then
    all_installed=0
    break
  fi
done < <(read_apps)

if (( all_installed )); then
  while IFS= read -r app; do
    [ -n "$app" ] || continue
    echo "already installed: $app"
  done < <(read_apps)
  exit 0
fi

remote_exists_in_scope() {
  local scope="$1"
  flatpak remotes "$scope" --columns=name 2>/dev/null | awk '{print $1}' | grep -qx flathub
}

run() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

if [ "$scope_flag" = "--user" ]; then
  if ! remote_exists_in_scope --user; then
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
else
  if ! remote_exists_in_scope --system; then
    run flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
fi

while IFS= read -r app; do
  [ -n "$app" ] || continue
  if flatpak info "$app" >/dev/null 2>&1; then
    echo "already installed: $app"
    continue
  fi
  run flatpak install -y "$scope_flag" flathub "$app"
done < <(read_apps)
