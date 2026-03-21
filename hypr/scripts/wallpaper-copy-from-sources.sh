#!/usr/bin/env bash
set -euo pipefail

src_root="${1:-$HOME/Pictures/wallpaper-sources}"
dst_root="${2:-$HOME/Pictures/wallpaper}"

if [ ! -d "$src_root" ]; then
  echo "Source root not found: $src_root" >&2
  exit 1
fi
mkdir -p "$dst_root/1080p" "$dst_root/4k"

read -r mon_w mon_h < <(
  hyprctl monitors -j 2>/dev/null | jq -r '((map(select(.focused==true))[0] // .[0]) | "\(.width) \(.height)")' 2>/dev/null || echo "1920 1080"
)

case "$mon_w $mon_h" in
  ''|'null null') mon_w=1920; mon_h=1080 ;;
esac

python3 - "$src_root" "$dst_root" "$mon_w" "$mon_h" <<'PY'
from PIL import Image
from pathlib import Path
import filecmp
import shutil
import sys

src_root = Path(sys.argv[1]).expanduser()
dst_root = Path(sys.argv[2]).expanduser()
mon_w = int(sys.argv[3])
mon_h = int(sys.argv[4])

target_ratio = mon_w / mon_h
ratio_tol = 0.12
exts = {".jpg", ".jpeg", ".png", ".webp"}

copied_1080p = 0
copied_4k = 0
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
    if ratio_diff > ratio_tol:
        skipped += 1
        continue

    if w >= 3840 and h >= 2160:
        bucket = "4k"
    elif w >= 1920 and h >= 1080:
        bucket = "1080p"
    else:
        skipped += 1
        continue

    target_dir = dst_root / bucket
    target_dir.mkdir(parents=True, exist_ok=True)
    base = p.name
    target = target_dir / base
    i = 1
    while target.exists():
        if filecmp.cmp(p, target, shallow=False):
            target = None
            break
        target = target_dir / f"{p.stem}-{i}{p.suffix}"
        i += 1

    if target is None:
        skipped += 1
        continue

    shutil.copy2(p, target)
    if bucket == "4k":
        copied_4k += 1
    else:
        copied_1080p += 1

print(f"Copied 1080p: {copied_1080p}")
print(f"Copied 4k: {copied_4k}")
print(f"Skipped: {skipped}")
print(f"Destination: {dst_root}")
PY
