#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"

command -v restic >/dev/null 2>&1 || {
  echo 'restic is required; install it with: sudo pacman -S restic' >&2
  exit 2
}
mkdir -p "$UNIT_DIR"
install -Dm644 "$REPO_DIR/setup/systemd/noxflow-client-backup.service" "$UNIT_DIR/noxflow-client-backup.service"
install -Dm644 "$REPO_DIR/setup/systemd/noxflow-client-backup.timer" "$UNIT_DIR/noxflow-client-backup.timer"
"$REPO_DIR/setup/client-backup.sh" init-config || true
systemctl --user daemon-reload
systemctl --user enable --now noxflow-client-backup.timer
systemctl --user list-timers --all --no-pager | rg 'noxflow-client-backup|NEXT|LAST' || true
