#!/usr/bin/env bash
set -euo pipefail

# Chrome with remote debugging for OpenCode browser MCP.
# Dedicated profile — normal browsing is unaffected.

PROFILE_DIR="${HOME}/.config/google-chrome-opencode"
mkdir -p "$PROFILE_DIR"

exec /opt/google/chrome/chrome \
  --ozone-platform-hint=auto \
  --no-first-run \
  --no-default-browser-check \
  --force-color-profile=srgb \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --remote-debugging-port=9222 \
  --user-data-dir="$PROFILE_DIR" \
  --disable-extensions \
  --disable-background-networking \
  --disable-default-apps \
  --disable-sync \
  --disable-translate \
  --mute-audio \
  --no-experiments \
  --no-pings \
  --no-sandbox \
  --safebrowsing-disable-auto-update \
  "$@"
