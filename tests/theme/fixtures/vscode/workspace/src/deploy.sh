#!/usr/bin/env bash
set -euo pipefail

readonly TARGET="${1:?usage: deploy.sh <target>}"
log() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }

for host in $(cat hosts.txt | grep -v '^#'); do
  if ssh "$host" "test -d /srv/$TARGET"; then
    log "deploying to $host"
    rsync -az --delete ./dist/ "$host:/srv/$TARGET/" || { log "failed: $host"; exit 1; }
  fi
done
