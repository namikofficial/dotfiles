#!/usr/bin/env bash
set -euo pipefail

src="${1:-}"
dst="${WALLPAPER_POOL_DIR:-$HOME/Pictures/wallpaper}"

if [ -z "$src" ]; then
  echo "Usage: $0 <source-dir>" >&2
  echo "Example: $0 \"$HOME/Pictures/wallpaper-sources/aesthetic-wallpapers\"" >&2
  exit 1
fi

if [ ! -d "$src" ]; then
  echo "Source dir not found: $src" >&2
  exit 1
fi

exec "$HOME/.config/hypr/scripts/wallpaper-copy-from-sources.sh" "$src" "$dst"
