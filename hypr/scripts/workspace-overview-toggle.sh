#!/usr/bin/env sh
set -eu

if [ -x "$HOME/.config/hypr/scripts/kage" ]; then
  if "$HOME/.config/hypr/scripts/kage" overview; then
    exit 0
  fi
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi
