#!/usr/bin/env bash
set -euo pipefail

dir="${1:-$HOME/Pictures/wallpaper}"
reject_root="${WALLPAPER_REJECT_DIR:-$HOME/Pictures/wallpaper_rejected}"

if [ ! -d "$dir" ]; then
  echo "Wallpaper dir not found: $dir" >&2
  exit 1
fi

read -r mon_w mon_h < <(
  hyprctl monitors -j 2>/dev/null | jq -r '((map(select(.focused==true))[0] // .[0]) | "\(.width) \(.height)")' 2>/dev/null || echo "1920 1080"
)

case "$mon_w $mon_h" in
  ''|'null null') mon_w=1920; mon_h=1080 ;;
esac

ts="$(date +%Y%m%d-%H%M%S)"
reject_dir="$reject_root/$ts"
mkdir -p "$reject_dir"

python3 - "$dir" "$reject_dir" "$mon_w" "$mon_h" <<'PY'
from PIL import Image
from pathlib import Path
import shutil
import sys

src = Path(sys.argv[1]).expanduser()
reject = Path(sys.argv[2]).expanduser()
mon_w = int(sys.argv[3])
mon_h = int(sys.argv[4])

target_ratio = mon_w / mon_h
ratio_tol = 0.18

exts = {".jpg", ".jpeg", ".png", ".webp"}
kept = 0
moved = 0

for p in sorted(src.iterdir()):
    if not p.is_file() or p.suffix.lower() not in exts:
        continue
    try:
        with Image.open(p) as im:
            w, h = im.size
    except Exception:
        dest = reject / p.name
        shutil.move(str(p), str(dest))
        moved += 1
        continue

    ratio = w / h if h else 0
    ratio_diff = abs(ratio - target_ratio)
    enough_pixels = (w >= mon_w and h >= mon_h)

    if ratio_diff <= ratio_tol and enough_pixels:
        kept += 1
        continue

    dest = reject / p.name
    i = 1
    while dest.exists():
      dest = reject / f"{p.stem}-{i}{p.suffix}"
      i += 1
    shutil.move(str(p), str(dest))
    moved += 1

print(f"Kept: {kept}")
print(f"Moved out: {moved}")
print(f"Rejected folder: {reject}")
PY
