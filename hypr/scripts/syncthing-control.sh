#!/usr/bin/env bash
set -euo pipefail

ui_url="${SYNCTHING_UI_URL:-http://127.0.0.1:8384/}"
config_file="${SYNCTHING_CONFIG_FILE:-$HOME/.local/state/syncthing/config.xml}"

open_ui() {
  local opener="${BROWSER:-}"
  if [ -z "$opener" ] && command -v xdg-open >/dev/null 2>&1; then opener="xdg-open"; fi
  if [ -z "$opener" ] && command -v gio >/dev/null 2>&1; then opener="gio open"; fi
  if [ -z "$opener" ] && command -v firefox >/dev/null 2>&1; then opener="firefox"; fi
  if [ -z "$opener" ] && command -v google-chrome-stable >/dev/null 2>&1; then opener="google-chrome-stable"; fi
  if [ -n "$opener" ]; then
    # Hyprland exec can have a reduced desktop environment; do not fail the
    # keybind when the opener exits asynchronously.
    sh -c "$opener \"\$1\" >/dev/null 2>&1 &" sh "$ui_url" || true
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m webbrowser "$ui_url" >/dev/null 2>&1 &
    return 0
  fi
  notify-send -a Syncthing "Syncthing" "Open $ui_url manually" >/dev/null 2>&1 || true
  return 1
}

get_primary_sync_dir() {
  python3 - "$config_file" <<'PY'
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

cfg = Path(sys.argv[1])
if not cfg.exists():
    print(str(Path.home() / "Sync"))
    raise SystemExit(0)

try:
    root = ET.parse(cfg).getroot()
except Exception:
    print(str(Path.home() / "Sync"))
    raise SystemExit(0)

folder = root.find("folder")
if folder is not None:
    path = folder.get("path")
    if path:
        print(path)
        raise SystemExit(0)

print(str(Path.home() / "Sync"))
PY
}

open_sync_dir() {
  local dir
  dir="$(get_primary_sync_dir)"
  [ -d "$dir" ] || mkdir -p "$dir"
  xdg-open "$dir" >/dev/null 2>&1 &
}

toggle_service() {
  if systemctl --user is-active --quiet syncthing.service; then
    systemctl --user stop syncthing.service
    notify-send -a Syncthing "Syncthing" "Service stopped" >/dev/null 2>&1 || true
  else
    systemctl --user start syncthing.service
    notify-send -a Syncthing "Syncthing" "Service started" >/dev/null 2>&1 || true
  fi
}

show_status() {
  systemctl --user status syncthing.service --no-pager | sed -n '1,20p'
}

menu() {
  local choice
  choice="$(
    printf '%s\n' \
      "Open Syncthing Dashboard" \
      "Open Primary Sync Folder" \
      "Toggle Syncthing Service" \
      "Restart Syncthing Service" \
      "Show Syncthing Service Status" \
      "Open Syncthing Config XML" |
      rofi -dmenu -i -p 'Syncthing' -theme "$HOME/.config/rofi/actions.rasi"
  )"

  case "${choice:-}" in
    "Open Syncthing Dashboard") open_ui ;;
    "Open Primary Sync Folder") open_sync_dir ;;
    "Toggle Syncthing Service") toggle_service ;;
    "Restart Syncthing Service")
      systemctl --user restart syncthing.service
      notify-send -a Syncthing "Syncthing" "Service restarted" >/dev/null 2>&1 || true
      ;;
    "Show Syncthing Service Status")
      kitty -e /usr/bin/zsh -lic "$0 status; read -r -p 'Press enter to close'" >/dev/null 2>&1 &
      ;;
    "Open Syncthing Config XML")
      xdg-open "$config_file" >/dev/null 2>&1 &
      ;;
  esac
}

case "${1:-menu}" in
  menu) menu ;;
  open-ui) open_ui ;;
  open-dashboard) open_ui ;;
  open-sync-dir) open_sync_dir ;;
  toggle) toggle_service ;;
  restart) systemctl --user restart syncthing.service ;;
  status) show_status ;;
  *)
    printf 'Usage: %s [menu|open-ui|open-sync-dir|toggle|restart|status]\n' "$0" >&2
    exit 1
    ;;
esac
