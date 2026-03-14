#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  cat <<'EOF'
Usage: game-on-dgpu <command> [args...]

Steam launch option:
  game-on-dgpu %command%
EOF
  exit 1
fi

exec prime-run mangohud "$@"
