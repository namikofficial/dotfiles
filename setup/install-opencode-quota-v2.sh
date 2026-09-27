#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/opencode-quota-v2"
commit="75d9b5dbc01ed2e3e4ad1a609f9203912a2a4f8f"
repo="https://github.com/dmmop/opencode-quota-v2.git"

if [[ -e "$state/.git" ]]; then
  if [[ -n "$(git -C "$state" status --porcelain)" ]]; then
    printf 'Quota checkout has local changes: %s\n' "$state" >&2
    exit 1
  fi
  git -C "$state" fetch --quiet origin "$commit"
  git -C "$state" checkout --quiet --detach "$commit"
else
  mkdir -p "$(dirname "$state")"
  git clone --quiet "$repo" "$state"
  git -C "$state" checkout --quiet --detach "$commit"
fi

cd "$state"
pnpm install --frozen-lockfile --ignore-scripts
pnpm run build
pnpm exec vitest run tests/tui-v2-commands.test.ts
node --check "$root/configs/opencode/plugins/quota-v2/command-filter.mjs"
printf 'OpenCode v2 quota installed at %s\n' "$state"
