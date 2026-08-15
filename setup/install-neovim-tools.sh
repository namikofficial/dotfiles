#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
tools_dir="$repo_dir/nvim/tools"

if ! command -v pnpm >/dev/null 2>&1; then
  printf 'pnpm is required to install Neovim language tools\n' >&2
  exit 127
fi

if [[ ! -f "$tools_dir/pnpm-lock.yaml" ]]; then
  pnpm --dir "$tools_dir" install --lockfile-only
fi

pnpm --dir "$tools_dir" install --frozen-lockfile --ignore-scripts
printf 'Neovim language tools are installed in %s\n' "$tools_dir"
