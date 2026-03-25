#!/usr/bin/env bash
set -euo pipefail

cfg="$HOME/.config/eww"
command -v eww >/dev/null 2>&1 || exit 0

eww --config "$cfg" close notif_center >/dev/null 2>&1 || true
eww --config "$cfg" close notif_backdrop >/dev/null 2>&1 || true
command -v hyprctl >/dev/null 2>&1 && hyprctl dispatch submap reset >/dev/null 2>&1 || true
