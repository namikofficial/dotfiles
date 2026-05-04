#!/usr/bin/env bash
set -euo pipefail

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl dispatch killactive >/dev/null 2>&1 || true
fi
