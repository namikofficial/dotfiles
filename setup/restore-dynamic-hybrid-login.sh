#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf 'Deprecated: hybrid login policy is managed by workstationctl.\n' >&2
exec "$SCRIPT_DIR/workstationctl" apply-system
