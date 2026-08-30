#!/usr/bin/env sh
set -eu

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
dotfiles_dir="$(cd -- "$script_dir/../.." && pwd)"

daemon_ctl="$dotfiles_dir/hypr/scripts/cliphist-daemon.sh"

$daemon_ctl start >/dev/null 2>&1 || true

ctl="$HOME/.local/bin/author-clipboard-ctl"
if [ ! -x "$ctl" ]; then
  ctl="$(command -v author-clipboard-ctl || true)"
fi

if [ -z "$ctl" ] || [ ! -x "$ctl" ]; then
  notify-send -a "Author Clipboard" "Clipboard picker unavailable" \
    "Install author-clipboard-ctl in ~/.local/bin."
  exit 1
fi

exec "$ctl" picker --menu rofi --source history
