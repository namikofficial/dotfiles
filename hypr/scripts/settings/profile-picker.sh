#!/usr/bin/env bash
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
SETTINGSCTL="$ROOT_DIR/hypr/scripts/settingsctl"

profile="$("$SETTINGSCTL" profile list | rofi -dmenu -i -p 'Select Profile' -theme "$HOME/.config/rofi/actions.rasi" || true)"
[[ -n "$profile" ]] || exit 0
"$SETTINGSCTL" profile apply "$profile"
"$SETTINGSCTL" apply all
