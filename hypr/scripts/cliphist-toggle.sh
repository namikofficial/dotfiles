#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
dotfiles_dir="$(cd -- "$script_dir/../.." && pwd)"

daemon_ctl="$dotfiles_dir/hypr/scripts/cliphist-daemon.sh"

$daemon_ctl start >/dev/null 2>&1 || true

picker="$HOME/.local/bin/author-clipboard-hypr-picker"
if [ ! -x "$picker" ]; then
  picker="$(command -v author-clipboard-hypr-picker || true)"
fi

if [ -z "$picker" ] || [ ! -x "$picker" ]; then
  notify-send -a "Author Clipboard" "Clipboard picker unavailable" \
    "Install author-clipboard-hypr-picker in ~/.local/bin."
  exit 1
fi

exec "$picker"
