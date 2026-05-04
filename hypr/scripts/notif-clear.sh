#!/usr/bin/env bash
set -euo pipefail

if command -v wayle >/dev/null 2>&1; then
  wayle notify dismiss-all >/dev/null 2>&1 || true
fi
