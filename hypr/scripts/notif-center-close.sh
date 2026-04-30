#!/usr/bin/env bash
set -euo pipefail

if command -v wayle >/dev/null 2>&1; then
  wayle panel toggle notifications >/dev/null 2>&1 || true
fi
