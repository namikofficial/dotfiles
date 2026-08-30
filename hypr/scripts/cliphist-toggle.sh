#!/usr/bin/env sh
set -eu

# The current native 0.6.0 picker starts its async service outside a Tokio
# runtime and can render an empty window before panicking. Route this alias to
# the CLI-backed picker, which uses the same Author Clipboard daemon/history
# and is verified live on Hyprland.
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/cliphist-rofi.sh"
