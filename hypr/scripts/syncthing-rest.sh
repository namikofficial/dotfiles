#!/usr/bin/env bash
set -euo pipefail

base_url="${SYNCTHING_API_URL:-http://127.0.0.1:8384}"
config_file="${SYNCTHING_CONFIG_FILE:-$HOME/.local/state/syncthing/config.xml}"

api_key() {
  python3 - "$config_file" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit(1)
root = ET.parse(path).getroot()
gui = root.find("gui")
key = gui.findtext("apikey", "") if gui is not None else ""
if not key:
    raise SystemExit(1)
print(key)
PY
}

request() {
  local method="$1" endpoint="$2"
  shift 2
  local key
  key="$(api_key)"
  curl -fsS --max-time 4 -X "$method" "$base_url$endpoint" \
    -H "X-API-Key: $key" -H "Content-Type: application/json" "$@"
}

snapshot() {
  local status connections folders devices events folder_statuses
  status="$(request GET /rest/system/status)"
  connections="$(request GET /rest/system/connections)"
  folders="$(request GET /rest/config/folders)"
  devices="$(request GET /rest/config/devices)"
  events="$(request GET '/rest/events?since=0&limit=30')"
  folder_statuses="$(python3 - "$folders" "$base_url" "$(api_key)" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

folders = json.loads(sys.argv[1])
base_url, key = sys.argv[2:]
result = {}
for folder in folders:
    folder_id = folder.get("id", "")
    if not folder_id:
        continue
    url = base_url + "/rest/db/status?folder=" + urllib.parse.quote(folder_id)
    try:
        req = urllib.request.Request(url, headers={"X-API-Key": key})
        with urllib.request.urlopen(req, timeout=4) as response:
            result[folder_id] = json.load(response)
    except Exception:
        result[folder_id] = {}
print(json.dumps(result, separators=(",", ":")))
PY
)"
  python3 - "$status" "$connections" "$folders" "$devices" "$events" "$folder_statuses" <<'PY'
import json
import sys

status, connections, folders, devices, events, folder_statuses = map(json.loads, sys.argv[1:])
conn = connections.get("connections", {})
folder_rows = []
for folder in folders:
    folder_id = folder.get("id", "")
    try:
        current = folder_statuses.get(folder_id, {})
        state = current.get("state", "unknown")
    except Exception:
        state = "unknown"
    folder_rows.append({
        "id": folder_id,
        "label": folder.get("label", folder_id),
        "path": folder.get("path", ""),
        "devices": [d.get("deviceID", "") for d in folder.get("devices", [])],
        "state": state,
        "completion": current.get("completion", 0),
        "needBytes": current.get("needBytes", 0),
        "inSyncBytes": current.get("inSyncBytes", 0),
        "paused": bool(folder.get("paused", False)),
    })
device_rows = []
for device in devices:
    device_id = device.get("deviceID", "")
    current = conn.get(device_id, {})
    device_rows.append({
        "id": device_id,
        "name": device.get("name", device_id[:10]),
        "address": (current.get("address") or "").split(" ")[0],
        "connected": current.get("connected", False),
        "paused": bool(device.get("paused", False)),
    })
print(json.dumps({
    "apiReachable": True,
    "myId": status.get("myID", ""),
    "myName": status.get("myID", "")[:12],
    "uptime": status.get("uptime", 0),
    "folders": folder_rows,
    "devices": device_rows,
    "events": events if isinstance(events, list) else [],
}, separators=(",", ":")))
PY
}

action() {
  local verb="$1" id="${2:-}"
  case "$verb" in
    pause) request POST "/rest/folder/pause?folder=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$id")" >/dev/null ;;
    resume) request POST "/rest/folder/resume?folder=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$id")" >/dev/null ;;
    rescan) request POST "/rest/folder/rescan?folder=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$id")" >/dev/null ;;
    restart) systemctl --user restart syncthing.service ;;
    toggle) if systemctl --user is-active --quiet syncthing.service; then systemctl --user stop syncthing.service; else systemctl --user start syncthing.service; fi ;;
    *) printf 'Usage: %s snapshot|pause|resume|rescan|restart|toggle [folder-id]\n' "$0" >&2; return 2 ;;
  esac
}

case "${1:-snapshot}" in
  snapshot) snapshot ;;
  pause|resume|rescan|restart|toggle) action "$@" ;;
  *) action "$@" ;;
esac
