#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf 'Deprecated: use workstationctl apply-system.\n' >&2
exec "$SCRIPT_DIR/workstationctl" apply-system
