#!/usr/bin/env bash
set -euo pipefail

ENTRY_DIR="/boot/loader/entries"
STAMP="$(date +%Y%m%d-%H%M%S)"
changed=0

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [ ! -d "$ENTRY_DIR" ]; then
  echo "systemd-boot entries directory not found: $ENTRY_DIR" >&2
  exit 1
fi

for entry in "$ENTRY_DIR"/*.conf; do
  [ -f "$entry" ] || continue

  # Skip backup snapshots and the explicit iGPU-safe profile.
  if [[ "$entry" == *.bak.* ]]; then
    continue
  fi

  if grep -Eiq '^title\s+.*iGPU safe' "$entry"; then
    echo "skip   $entry (iGPU-safe profile)"
    continue
  fi

  cp "$entry" "${entry}.bak.${STAMP}"

  if grep -q 'nvidia-drm.modeset=' "$entry"; then
    sed -i -E 's/nvidia-drm\.modeset=[01]/nvidia-drm.modeset=1/g' "$entry"
  else
    sed -i -E '/^options\s+/ s|$| nvidia-drm.modeset=1|' "$entry"
  fi

  changed=1
  echo "fix    $entry"
done

if (( changed == 0 )); then
  echo "No boot entries updated."
  exit 0
fi

echo "Done. Reboot to apply modesetting changes."
