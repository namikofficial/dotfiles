#!/usr/bin/env bash
set -euo pipefail

code_bin="${VSCODE_BIN:-/usr/bin/code}"
if [ ! -x "$code_bin" ]; then
  code_bin="$(command -v code || true)"
fi

if [ -z "$code_bin" ] || [ ! -x "$code_bin" ]; then
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -a "VS Code" "VS Code not found" "Install package: code"
  exit 1
fi

# Wayland-first + consistent rendering without noisy CLI warnings.
export ELECTRON_OZONE_PLATFORM_HINT=auto
export OZONE_PLATFORM=wayland

exec "$code_bin" "$@"
