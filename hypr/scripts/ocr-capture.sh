#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a OCR "$1" "${2:-}"
}

for cmd in grim slurp tesseract wl-copy; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    notify "Missing dependency" "Install: $cmd"
    exit 1
  fi
done

img="$(mktemp --suffix=.png)"
txt="$(mktemp --suffix=.txt)"
cleanup() {
  rm -f "$img" "$txt"
}
trap cleanup EXIT INT TERM

region="$(slurp 2>/dev/null || true)"
[ -n "$region" ] || exit 0

grim -g "$region" "$img"
tesseract "$img" stdout -l eng --oem 1 --psm 6 2>/dev/null >"$txt" || true

# Trim blank lines and trailing whitespace.
cleaned="$(sed 's/[[:space:]]\+$//; /^[[:space:]]*$/d' "$txt" | tr -s '\n')"
if [ -z "$cleaned" ]; then
  notify "No text detected"
  exit 0
fi

printf '%s' "$cleaned" | wl-copy
preview="$(printf '%s' "$cleaned" | head -c 120)"
notify "OCR copied to clipboard" "$preview"
