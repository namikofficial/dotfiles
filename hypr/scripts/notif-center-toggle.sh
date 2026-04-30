#!/usr/bin/env bash
set -euo pipefail

panel_switch="${HOME}/.config/hypr/scripts/panel-switch.sh"

if command -v wayle >/dev/null 2>&1; then
  if pgrep -x wayle >/dev/null 2>&1 || { [ -x "$panel_switch" ] && "$panel_switch" status 2>/dev/null | grep -q '^wayle:visible$'; }; then
    wayle panel show >/dev/null 2>&1 || true
    wayle panel toggle notifications >/dev/null 2>&1 && exit 0
    wayle panel toggle notification >/dev/null 2>&1 && exit 0
  fi
fi
