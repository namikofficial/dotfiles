#!/usr/bin/env bash
# wallpaper-add.sh — add one image to the handpicked pool.
# Creates a 4k copy and a 1080p LANCZOS-downscaled copy.
# Usage: wallpaper-add.sh <path-to-image>
# Example: wallpaper-add.sh ~/Downloads/my-wallpaper.png

set -euo pipefail

src="${1:-}"
pool_4k="$HOME/Pictures/wallpaper/handpicked/4k"
pool_1080p="$HOME/Pictures/wallpaper/handpicked/1080p"

usage() {
  echo "Usage: $0 <path-to-image>" >&2
  echo "Example: $0 ~/Downloads/my-wallpaper.png" >&2
  exit 1
}

if [ -z "$src" ]; then
  usage
fi

if [ ! -f "$src" ]; then
  echo "Error: not a file: $src" >&2
  exit 1
fi

ext="$(echo "${src##*.}" | tr '[:upper:]' '[:lower:]')"
case "$ext" in
  png | jpg | jpeg | webp) ;;
  *)
    echo "Error: unsupported extension .$ext (need png, jpg, jpeg, or webp)" >&2
    exit 1
    ;;
esac

# Determine next free two-digit number in the 4k pool.
# Avoids pipelines into while-read (subshell would lose max assignment).
next_num() {
  local dir="$1"
  local max=0 n
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    n="$(basename "$f" | sed 's/^\([0-9]\{2\}\)\..*/\1/' | sed 's/^0//')"
    [ -n "$n" ] && [ "$n" -gt "$max" ] 2>/dev/null && max="$n"
  done
  printf '%02d' $((max + 1))
}

mkdir -p "$pool_4k" "$pool_1080p"

num="$(next_num "$pool_4k")"

# Build a slug from the source filename (strip extension, lowercase, spaces→-).
slug="$(basename "$src" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_')"
stem="${num}. ${slug}"
dest_4k="${pool_4k}/${stem}.jpg"

cp "$src" "$dest_4k"
echo "[4k]   → $dest_4k"

# Write a 1080p LANCZOS-downscaled copy via Pillow (same style as set-wallpaper.sh).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$src" "$pool_1080p/${stem}.jpg" <<'PY'
import sys
from PIL import Image, ImageOps

src_path = sys.argv[1]
dst_path = sys.argv[2]
target_w, target_h = 1920, 1080

try:
    with Image.open(src_path) as im:
        im = ImageOps.exif_transpose(im)
        if "A" in im.getbands():
            flattened = Image.new("RGB", im.size, (11, 15, 24))
            flattened.paste(im.convert("RGBA"), mask=im.getchannel("A"))
            im = flattened
        else:
            im = im.convert("RGB")

        im.thumbnail((target_w, target_h), Image.Resampling.LANCZOS)
        im.save(dst_path, "JPEG", quality=95)
    print(f"[1080p] → {dst_path}")
except Exception as e:
    print(f"[warn] 1080p variant skipped ({e})", file=sys.stderr)
    import os
    os.unlink(dst_path)
    sys.exit(1)
PY
  echo "[done] $slug added to handpicked pool"
else
  echo "[warn] python3 not available — 1080p variant not generated"
  echo "[done] $slug added to handpicked pool (4k only)"
fi
