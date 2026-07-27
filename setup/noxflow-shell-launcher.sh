#!/usr/bin/env bash
set -euo pipefail

if ! command -v quickshell >/dev/null 2>&1; then
  echo "quickshell is required to start NoxFlow" >&2
  exit 127
fi

exec quickshell --path "${XDG_CONFIG_HOME:-$HOME/.config}/noxflow/shell"
