#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gtk_browser="$script_dir/cliphist-ui.py"
daemon_ctl="$script_dir/cliphist-daemon.sh"
ipc="$script_dir/cliphist-ipc.py"

if [ "${1:-}" != "--rofi" ] && command -v python3 >/dev/null 2>&1 && [ -f "$gtk_browser" ]; then
  if python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")' >/dev/null 2>&1; then
    if [ -x "$daemon_ctl" ] && [ -f "$ipc" ]; then
      "$daemon_ctl" start >/dev/null 2>&1 || true
      python3 "$ipc" show >/dev/null 2>&1 && exit 0
    fi
    python3 "$gtk_browser" "$@" && exit 0
  fi
fi

if ! command -v cliphist >/dev/null 2>&1; then
  exit 0
fi

tmp="${XDG_RUNTIME_DIR:-/tmp}/cliphist-rofi.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

cliphist -preview-width 320 list | awk -F '\t' '
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
