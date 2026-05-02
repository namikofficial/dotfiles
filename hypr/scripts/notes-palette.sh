#!/usr/bin/env bash
set -euo pipefail

choice="$(
  cat <<'EOF' | rofi -dmenu -i -no-show-icons -p 'Notes' -theme "$HOME/.config/rofi/actions.rasi"
open notes
create note from clipboard
EOF
)"
[ -n "${choice:-}" ] || exit 0

case "$choice" in
  "open notes") exec "$HOME/.config/hypr/scripts/open-notes.sh" ;;
  "create note from clipboard")
    exec kitty --title "clipboard note" -e bash -lc 'text="$(wl-paste -n 2>/dev/null || true)"; file="$HOME/Documents/notes/clipboard-$(date +%Y%m%d-%H%M%S).md"; printf "# Clipboard Note\n\n%s\n" "$text" > "$file"; command -v code >/dev/null 2>&1 && code "$file" >/dev/null 2>&1 &'
    ;;
esac
