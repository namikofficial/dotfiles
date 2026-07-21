#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$ROOT_DIR/setup/generate-keybind-docs.py" --check
rg -q '^\| `Super \+ 0` \| Focus workspace \| `10` \|' "$ROOT_DIR/docs/KEYBINDS.md"
rg -q '^\| `XF86AudioRaiseVolume` \|' "$ROOT_DIR/docs/KEYBINDS.md"
rg -q '<!-- BEGIN GENERATED HYPRLAND KEYBINDS -->' "$ROOT_DIR/docs/KEYBINDS.md"
rg -q '<!-- END GENERATED HYPRLAND KEYBINDS -->' "$ROOT_DIR/docs/KEYBINDS.md"

echo "keybind documentation smoke test passed"
