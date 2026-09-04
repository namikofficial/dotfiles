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

if ssh -o BatchMode=yes -o ConnectTimeout=5 noxorigin 'true' >/dev/null 2>&1; then
  printf 'SSH alias noxorigin: OK\n'
else
  printf 'SSH alias noxorigin: unavailable (configure ~/.ssh/config separately)\n' >&2
  exit 1
fi

printf '\nNext: cd %s && just doctor\n' "$NOXORIGIN_REPO"
