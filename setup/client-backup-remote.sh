#!/usr/bin/env bash
# Install this root-owned helper on each backup source host at
# /usr/local/libexec/client-db-backup-dump. Its companion configuration belongs
# in /etc/nox-backup/targets.conf (mode 600) and is intentionally not tracked.
set -euo pipefail

CONFIG=/etc/nox-backup/targets.conf
[ -r "$CONFIG" ] || { echo "missing $CONFIG" >&2; exit 2; }
# shellcheck disable=SC1090
source "$CONFIG"

check=0
if [ "${1:-}" = --check ]; then check=1; shift; fi
project="${1:-}"
environment="${2:-}"
key="$project:$environment"
command="${BACKUP_DUMP_COMMANDS[$key]:-}"
[ -n "$command" ] || { echo "backup target is not allow-listed: $key" >&2; exit 2; }

if [ "$check" -eq 1 ]; then
  bash -n <<<"$command"
  exit 0
fi
exec bash -lc "$command"
