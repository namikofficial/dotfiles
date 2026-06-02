#!/usr/bin/env bash
set -euo pipefail

if command -v hyprlauncher >/dev/null 2>&1; then
  exec hyprlauncher
fi

exec "$HOME/.config/hypr/scripts/launcher.sh" --fast
