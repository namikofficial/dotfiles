#!/usr/bin/env bash
set -euo pipefail

cfg="$HOME/.config/eww"
command -v eww >/dev/null 2>&1 || exit 0

eww --config "$cfg" close notif_toast >/dev/null 2>&1 || true
