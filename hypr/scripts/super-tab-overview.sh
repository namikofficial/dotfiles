#!/usr/bin/env bash
set -euo pipefail

# Compatibility entrypoint for older keybinds. Nox Atlas remains the sole
# visual window/workspace overview implementation.
exec "$HOME/.local/bin/noxctl" panel toggle atlas
