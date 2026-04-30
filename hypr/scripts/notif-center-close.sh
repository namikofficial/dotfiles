#!/usr/bin/env bash
set -euo pipefail

if command -v swaync-client >/dev/null 2>&1; then
  swaync-client -sw -cp >/dev/null 2>&1 || true
fi
