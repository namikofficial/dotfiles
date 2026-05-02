#!/usr/bin/env bash
set -euo pipefail

mode="${1:-shell}"

open_rofi() {
  rofi -dmenu -i -p "$1" -theme "$HOME/.config/rofi/actions.rasi"
}

shell_search() {
  if command -v atuin >/dev/null 2>&1; then
    exec kitty --title "Shell History" -e atuin search
  fi
  exec kitty --title "Shell History" -e bash -lc 'history | tail -n 2000 | fzf'
}

browser_search() {
  if command -v sqlite3 >/dev/null 2>&1; then
    db="${HOME}/.config/google-chrome/Default/History"
    [ -f "$db" ] || db="${HOME}/.mozilla/firefox/*.default-release/places.sqlite"
    exec kitty --title "Browser History" -e bash -lc '
      shopt -s nullglob
      dbs=("$HOME/.config/google-chrome/Default/History" "$HOME/.config/chromium/Default/History" "$HOME/.mozilla/firefox/"*.default*/places.sqlite)
      for db in "${dbs[@]}"; do
        [ -f "$db" ] || continue
        sqlite3 "$db" "select url, title from urls order by last_visit_time desc limit 200" 2>/dev/null | fzf
        exit 0
      done
      echo "No browser history database found"
      read -r -p "press enter..."
    '
  fi
  exec kitty --title "Browser History" -e bash -lc 'echo "sqlite3 unavailable"; read -r -p "press enter..."'
}

case "$mode" in
  shell) shell_search ;;
  browser) browser_search ;;
  *)
    choice="$(printf '%s\n' shell browser | open_rofi 'History')"
    [ -n "$choice" ] || exit 0
    exec "$0" "$choice"
    ;;
esac
