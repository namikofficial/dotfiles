#!/usr/bin/env bash
set -euo pipefail

WITH_HYPRSPACE=0

for arg in "$@"; do
  case "$arg" in
    --with-hyprspace) WITH_HYPRSPACE=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--with-hyprspace]" >&2
      exit 1
      ;;
  esac
done

if ! command -v hyprpm >/dev/null 2>&1; then
  echo "hyprpm not found (install/launch Hyprland first)." >&2
  exit 1
fi

cache_dir="/var/cache/hyprpm/${USER}"
if [ -d "$cache_dir" ] && [ ! -w "$cache_dir" ]; then
  echo "hyprpm cache is not writable: $cache_dir" >&2
  echo "fix with: sudo chown -R $USER:$USER $cache_dir" >&2
  exit 1
fi

if ! hyprpm list 2>/dev/null | grep -q 'Repository hyprland-plugins'; then
  hyprpm add https://github.com/hyprwm/hyprland-plugins
fi

hyprpm update
hyprpm enable hyprexpo

if (( WITH_HYPRSPACE )); then
  if ! hyprpm list 2>/dev/null | grep -q 'Repository Hyprspace'; then
    hyprpm add https://github.com/KZDKM/Hyprspace || true
  fi
  hyprpm enable Hyprspace || {
    echo "warning: Hyprspace failed to build/enable on current Hyprland version." >&2
  }
fi

echo "Hypr plugins installed."
