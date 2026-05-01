#!/usr/bin/env sh
set -eu

if [ -x "$HOME/.config/hypr/scripts/kage" ]; then
  exec "$HOME/.config/hypr/scripts/kage" overview
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi
