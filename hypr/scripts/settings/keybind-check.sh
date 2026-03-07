#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
CONF="$ROOT_DIR/hypr/hyprland.conf"

if [[ ! -f "$CONF" ]]; then
  echo "Missing hyprland.conf at $CONF" >&2
  exit 1
fi

awk -F',' '
/^bind|^binde|^bindm|^bindl|^bindel/ {
  lhs=$1
  gsub(/^[^=]*=/,"",lhs)
  gsub(/^ +| +$/,"",lhs)
  key=$2
  gsub(/^ +| +$/,"",key)
  print lhs"+"key
}' "$CONF" \
  | sort \
  | uniq -d \
  | sed 's/^/DUPLICATE: /' || true
