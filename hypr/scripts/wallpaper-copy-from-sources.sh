#!/usr/bin/env bash
set -euo pipefail

src_root="${1:-$HOME/Pictures/wallpaper-sources}"
dst="${2:-$HOME/Pictures/wallpaper}"

if [ ! -d "$src_root" ]; then
  echo "Source root not found: $src_root" >&2
  exit 1
fi
mkdir -p "$dst"

read -r mon_w mon_h < <(
  hyprctl monitors -j 2>/dev/null | jq -r '((map(select(.focused==true))[0] // .[0]) | "\(.width) \(.height)")' 2>/dev/null || echo "1920 1080"
)

case "$mon_w $mon_h" in
  ''|'null null') mon_w=1920; mon_h=1080 ;;
esac

python3 - "$src_root" "$dst" "$mon_w" "$mon_h" <<'PY'
from PIL import Image
from pathlib import Path
import shutil
import sys

src_root = Path(sys.argv[1]).expanduser()
dst = Path(sys.argv[2]).expanduser()
mon_w = int(sys.argv[3])
mon_h = int(sys.argv[4])

target_ratio = mon_w / mon_h
ratio_tol = 0.18
exts = {".jpg", ".jpeg", ".png", ".webp"}

copied = 0
skipped = 0

for p in sorted(src_root.rglob("*")):
    if not p.is_file() or p.suffix.lower() not in exts:
        continue
    if "/.git/" in str(p):
        continue
    try:
        with Image.open(p) as im:
            w, h = im.size
    except Exception:
        skipped += 1
        continue

    ratio = w / h if h else 0
    ratio_diff = abs(ratio - target_ratio)
    enough_pixels = (w >= mon_w and h >= mon_h)
    if not (ratio_diff <= ratio_tol and enough_pixels):
        skipped += 1
        continue

    base = p.name
    target = dst / base
    i = 1
    while target.exists():
        target = dst / f"{p.stem}-{i}{p.suffix}"
        i += 1

    shutil.copy2(p, target)
    copied += 1

print(f"Copied: {copied}")
print(f"Skipped: {skipped}")
print(f"Destination: {dst}")
PY
