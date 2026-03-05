#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_SRC_DIR="$REPO_DIR/setup/systemd"
UNIT_DST_DIR="$HOME/.config/systemd/user"

mkdir -p "$UNIT_DST_DIR"

install -Dm644 "$UNIT_SRC_DIR/noxflow-weekly-health.service" "$UNIT_DST_DIR/noxflow-weekly-health.service"
install -Dm644 "$UNIT_SRC_DIR/noxflow-weekly-health.timer" "$UNIT_DST_DIR/noxflow-weekly-health.timer"

systemctl --user daemon-reload
systemctl --user enable --now noxflow-weekly-health.timer

echo "Enabled: noxflow-weekly-health.timer"
systemctl --user list-timers --all --no-pager | rg 'noxflow-weekly-health|NEXT|LAST' || true
