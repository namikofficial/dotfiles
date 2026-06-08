#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
dotfiles_dir="$(cd -- "$script_dir/../.." && pwd)"

daemon_ctl="$dotfiles_dir/hypr/scripts/cliphist-daemon.sh"

$daemon_ctl start >/dev/null 2>&1 || true

author-clipboard-ctl picker --menu rofi --source history