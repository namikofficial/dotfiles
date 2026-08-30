#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
dry_run=0

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi
if (($# != 0)); then
  printf 'Usage: %s [--dry-run]\n' "$0" >&2
  exit 64
fi

mkdir -p "$bin_dir"

link_bridge() {
  local source="$1"
  local target="$2"
  if ((dry_run)); then
    printf '[dry-run] ln -sfn %q %q\n' "$source" "$target"
    return
  fi
  ln -sfn "$source" "$target"
  printf 'link %s -> %s\n' "$target" "$source"
}

link_bridge "$repo_dir/system/node-runtime" "$bin_dir/node"
link_bridge "$repo_dir/system/node-runtime" "$bin_dir/npm"
link_bridge "$repo_dir/system/node-runtime" "$bin_dir/npx"
link_bridge "$repo_dir/system/pnpm" "$bin_dir/pnpm"
link_bridge "$repo_dir/system/desktop-launch" "$bin_dir/desktop-launch"
link_bridge "$repo_dir/system/code" "$bin_dir/code"
