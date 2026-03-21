#!/usr/bin/env bash
set -euo pipefail

obs_bin="${OBSIDIAN_BIN:-/usr/bin/obsidian}"
if [ ! -x "$obs_bin" ]; then
  obs_bin="$(command -v obsidian || true)"
fi

if [ -z "$obs_bin" ] || [ ! -x "$obs_bin" ]; then
  command -v notify-send >/dev/null 2>&1 && \
    notify-send -a "Obsidian" "Obsidian not found" "Install package: obsidian"
  exit 1
fi

export ELECTRON_OZONE_PLATFORM_HINT=auto
export OZONE_PLATFORM=wayland

default_flags=(
  --ozone-platform-hint=auto
  --enable-features=UseOzonePlatform,WaylandWindowDecorations
  --enable-gpu-rasterization
  --enable-zero-copy
)

exec "$obs_bin" "${default_flags[@]}" "$@"
