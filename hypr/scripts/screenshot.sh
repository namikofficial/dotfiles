#!/usr/bin/env sh
set -eu

mode="${1:-area}"
out_dir="$HOME/Pictures/Screenshots"
mkdir -p "$out_dir"
file="$out_dir/$(date +%Y-%m-%d_%H-%M-%S).png"
tmp_file="$(mktemp --suffix=.png)"

is_custom_mode() {
  [ -x "$HOME/.config/hypr/scripts/notif-peek.sh" ] && \
    [ "$("$HOME/.config/hypr/scripts/notif-peek.sh" mode 2>/dev/null || echo custom)" = "custom" ]
}

emit() {
  level="$1"
  title="$2"
  body="${3:-}"
  if [ -x "$HOME/.config/hypr/scripts/lib/log.sh" ]; then
    "$HOME/.config/hypr/scripts/lib/log.sh" --emit "$level" screenshot "$title" "$body" "" "$body" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT INT TERM

if [ "$mode" = "full" ]; then
  grim "$tmp_file"
else
  region="$(slurp 2>/dev/null || true)"
  [ -n "$region" ] || exit 0
  grim -g "$region" "$tmp_file"
fi

annotated=0
if [ "$mode" = "area" ] && command -v satty >/dev/null 2>&1; then
  if satty --filename "$tmp_file" --output-filename "$file" >/dev/null 2>&1; then
    annotated=1
  fi
fi

if [ "$annotated" -eq 0 ] && [ "$mode" = "area" ] && command -v swappy >/dev/null 2>&1; then
  if swappy -f "$tmp_file" -o "$file" >/dev/null 2>&1; then
    annotated=1
  fi
fi

if [ "$annotated" -eq 0 ]; then
  cp "$tmp_file" "$file"
fi

if command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$file"
fi

if ! is_custom_mode && command -v notify-send >/dev/null 2>&1; then
  notify-send "Screenshot saved" "$file"
fi
emit info "Screenshot saved" "$file"
