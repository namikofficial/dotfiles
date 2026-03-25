#!/usr/bin/env sh
set -eu

notify() {
  if [ -x "$HOME/.config/hypr/scripts/notif-peek.sh" ] && \
    [ "$("$HOME/.config/hypr/scripts/notif-peek.sh" mode 2>/dev/null || echo custom)" = "custom" ]; then
    return 0
  fi
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a OCR "$1" "${2:-}"
}

emit() {
  level="$1"
  title="$2"
  body="${3:-}"
  if [ -x "$HOME/.config/hypr/scripts/lib/log.sh" ]; then
    "$HOME/.config/hypr/scripts/lib/log.sh" --emit "$level" ocr "$title" "$body" "" "$body" >/dev/null 2>&1 || true
  fi
}

for cmd in grim slurp tesseract wl-copy python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    notify "Missing dependency" "Install: $cmd"
    emit error "OCR dependency missing" "Install: $cmd"
    exit 1
  fi
done

img="$(mktemp --suffix=.png)"
img_proc="$(mktemp --suffix=.png)"
txt="$(mktemp --suffix=.txt)"
cleanup() {
  rm -f "$img" "$img_proc" "$txt"
}
trap cleanup EXIT INT TERM

region="$(slurp 2>/dev/null || true)"
[ -n "$region" ] || exit 0

# Capture at 2× scale — higher resolution = dramatically better OCR accuracy.
grim -g "$region" -s 2 "$img"

# Pre-process: grayscale → auto-contrast → sharpen → 20px white padding.
# Tesseract accuracy improves significantly with these steps.
python3 - "$img" "$img_proc" <<'PY'
import sys
from PIL import Image, ImageFilter, ImageEnhance, ImageOps

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("L")               # grayscale
img = ImageOps.autocontrast(img, cutoff=1)        # stretch contrast
img = ImageEnhance.Sharpness(img).enhance(2.0)    # sharpen edges
# Add white border so Tesseract doesn't clip edge characters
padded = Image.new("L", (img.width + 40, img.height + 40), 255)
padded.paste(img, (20, 20))
padded.save(dst, dpi=(300, 300))
PY

# PSM 3 = fully automatic layout detection (better for mixed code+text).
# PSM 6 = uniform block — good for single paragraphs but misses code structure.
tesseract "$img_proc" stdout -l eng --oem 1 --psm 3 2>/dev/null >"$txt" || true

# Trim blank lines and trailing whitespace.
cleaned="$(sed 's/[[:space:]]\+$//; /^[[:space:]]*$/d' "$txt" | tr -s '\n')"
if [ -z "$cleaned" ]; then
  notify "No text detected" "Try selecting a region with clearer contrast"
  emit warn "OCR no text detected" "Try selecting a region with clearer contrast"
  exit 0
fi

printf '%s' "$cleaned" | wl-copy
char_count="$(printf '%s' "$cleaned" | wc -c)"
preview="$(printf '%s' "$cleaned" | head -c 120)"
notify "OCR copied  (${char_count} chars)" "$preview"
emit info "OCR copied (${char_count} chars)" "$preview"
