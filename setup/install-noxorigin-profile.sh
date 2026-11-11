#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOXORIGIN_REPO="${NOXORIGIN_REPO:-$HOME/Documents/code/noxorigin/noxorigin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/noxorigin"

if [[ ! -d "$NOXORIGIN_REPO" || ! -f "$NOXORIGIN_REPO/justfile" ]]; then
  printf 'NoxOrigin repository not found: %s\nSet NOXORIGIN_REPO and retry.\n' "$NOXORIGIN_REPO" >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"
ln -sfn "$NOXORIGIN_REPO" "$CONFIG_DIR/repo-root"
printf 'NoxOrigin repo link: %s -> %s\n' "$CONFIG_DIR/repo-root" "$NOXORIGIN_REPO"

# `nox` is the current server. `noxorigin` is the previous one, kept as the
# rollback path during a migration, so both are probed and neither is required.
ssh_status=0
for alias in nox noxorigin; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$alias" 'true' >/dev/null 2>&1; then
    printf 'SSH alias %-10s OK\n' "$alias"
  else
    printf 'SSH alias %-10s unreachable\n' "$alias"
    ssh_status=1
  fi
done

if [ "$ssh_status" -ne 0 ]; then
  printf '\nAt least one server alias is unreachable. Check ~/.ssh/config, or install the\n' >&2
  printf 'managed config with: %s/setup/install-ssh-config.sh\n' "$REPO_DIR" >&2
  printf 'If the new VPS has not accepted the public key yet, see Phase 0 of\n' >&2
  printf 'noxorigin/docs/VPS_MIGRATION_PLAN.md.\n' >&2
  exit 1
fi

printf '\nNext: cd %s && just doctor\n' "$NOXORIGIN_REPO"
