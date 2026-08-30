#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${PLANNOTATOR_DATA_DIR:-$HOME/.plannotator}/hooks/compound"
mkdir -p "$TARGET_DIR"
install -m 0644 \
  "$REPO_DIR/configs/plannotator/compound/enterplanmode-improve-hook.txt" \
  "$TARGET_DIR/enterplanmode-improve-hook.txt"
printf 'Installed Plannotator improvement hook at %s\n' "$TARGET_DIR/enterplanmode-improve-hook.txt"
