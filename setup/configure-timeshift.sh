#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SYSTEMD_DIR="$SCRIPT_DIR/systemd"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/timeshift-setup-${TS}.log"
LATEST_LINK="$LOG_DIR/timeshift-setup-latest.log"
CONFIG_FILE="/etc/timeshift/timeshift.json"
DEFAULT_FILE="/etc/timeshift/default.json"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Timeshift setup ($(date -u '+%F %T UTC')) ==="
echo "repo: $REPO_DIR"
echo "log:  $LOG_FILE"
echo

if ! command -v timeshift >/dev/null 2>&1; then
  echo "timeshift is not installed."
  echo "Install it with: sudo pacman -S timeshift"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  if [[ -f "$DEFAULT_FILE" ]]; then
    install -m 644 "$DEFAULT_FILE" "$CONFIG_FILE"
  else
    echo "Missing timeshift default config at $DEFAULT_FILE"
    exit 1
  fi
fi

cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.${TS}"

python3 - "$CONFIG_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
updates = {
    "do_first_run": "false",
    "schedule_hourly": "false",
    "schedule_daily": "true",
    "schedule_weekly": "false",
    "schedule_monthly": "false",
    "schedule_boot": "false",
    "count_hourly": "0",
    "count_daily": "5",
    "count_weekly": "0",
    "count_monthly": "0",
    "count_boot": "0",
    "stop_cron_emails": "true",
}
data.update(updates)
path.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "Updated $CONFIG_FILE:"
sed -n '1,120p' "$CONFIG_FILE"
echo

echo "Installing systemd timer/service..."
install -Dm644 "$SYSTEMD_DIR/noxflow-timeshift-auto.service" /etc/systemd/system/noxflow-timeshift-auto.service
install -Dm644 "$SYSTEMD_DIR/noxflow-timeshift-auto.timer" /etc/systemd/system/noxflow-timeshift-auto.timer
systemctl daemon-reload
systemctl enable --now noxflow-timeshift-auto.timer
systemctl status --no-pager noxflow-timeshift-auto.timer | sed -n '1,14p'
echo

echo "Running one scheduler check now..."
timeshift --check --scripted || true
echo

echo "Next timer runs:"
systemctl list-timers --all --no-pager | rg 'noxflow-timeshift-auto|NEXT|LAST' || true
echo

ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LINK"
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${SUDO_USER}:${SUDO_USER}" "$LOG_FILE" "$LATEST_LINK" 2>/dev/null || true
fi

echo "Done."
echo "Latest log: $LATEST_LINK"
