#!/usr/bin/env sh
set -eu

if ! command -v cliphist >/dev/null 2>&1; then
  exit 0
fi

tmp="${XDG_RUNTIME_DIR:-/tmp}/cliphist-rofi.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

cliphist list | awk -F '\t' '
  {
    id=$1
    $1=""
    sub(/^\t/, "", $0)
    gsub(/\r/, " ", $0)
    txt=$0
    if (length(txt) > 140) txt=substr(txt, 1, 140) "..."
    printf "%d\t%s\t%s\n", NR, id, txt
  }
' > "$tmp"

[ -s "$tmp" ] || exit 0

choice="$(
  awk -F '\t' '{printf "%d  %s\n", $1, $3}' "$tmp" \
    | rofi -dmenu -i -p "Clipboard" -theme "$HOME/.config/rofi/cliphist.rasi"
)"
[ -n "${choice:-}" ] || exit 0

idx="$(printf '%s\n' "$choice" | awk '{print $1}')"
[ -n "${idx:-}" ] || exit 0

entry_id="$(awk -F '\t' -v n="$idx" '$1==n {print $2; exit}' "$tmp")"
[ -n "${entry_id:-}" ] || exit 0

cliphist decode "$entry_id" | wl-copy
