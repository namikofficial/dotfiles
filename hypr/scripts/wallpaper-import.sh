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

mkdir -p "$dst"

count=0
while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  target="$dst/$base"

  if [ -e "$target" ]; then
    stem="${base%.*}"
    ext="${base##*.}"
    i=1
    while [ -e "$dst/${stem}-${i}.${ext}" ]; do
      i=$((i + 1))
    done
    target="$dst/${stem}-${i}.${ext}"
  fi

  cp -n "$file" "$target" && count=$((count + 1))
done < <(find "$src" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

echo "Imported $count wallpapers into: $dst"
