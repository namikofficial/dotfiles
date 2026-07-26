#!/usr/bin/env bash
set -euo pipefail

root="${WALL_SOURCE_ROOT:-$HOME/Pictures/wallpaper-sources}"
mkdir -p "$root"
git_timeout="${WALL_GIT_TIMEOUT_SECONDS:-900}"
update_existing="${WALL_UPDATE_EXISTING:-0}"

clone_or_update() {
  local name="$1"
  local url="$2"
  local dir="$root/$name"

  if [ -d "$dir/.git" ]; then
    if [ "$update_existing" = "1" ]; then
      echo "[update] $name"
      timeout "$git_timeout" git -C "$dir" pull --ff-only || true
    else
      echo "[skip]   $name (already downloaded)"
    fi
    return 0
  fi

  echo "[clone]  $name"
  timeout "$git_timeout" git clone --depth 1 "$url" "$dir" || {
    echo "[warn] failed: $url" >&2
    return 0
  }
}

# Naruto, Death Note, and other anime wallpapers.
clone_or_update "anime-wallpapers"       "https://github.com/erickmartin890/Anime-Wallpapers.git"

# Synthwave, dracula, gruvbox, catppuccin themes.
clone_or_update "wallz"                  "https://github.com/fr0st-xyz/wallz.git"

# Has dedicated coding/ and abstract/ subdirs for programming/tech wallpapers.
clone_or_update "usman-wallpapers"       "https://github.com/usman-369/wallpapers.git"

# Synthwave, cyberpunk, neon — great for that retro-wave feel.
clone_or_update "cybrpapers"             "https://github.com/cybrcore/cybrpapers.git"

cat >"$root/WEB_SOURCES.txt" <<'SOURCES'
Non-git wallpaper sources to browse manually:
- https://wallhaven.cc
- https://wall.alphacoders.com
- https://reddit.com/r/unixporn
- https://reddit.com/r/wallpaper
- https://reddit.com/r/wallpapers

Tip:
- Review in source folders first.
- Import reviewed wallpapers into the curated 1080p/4k pool with:
  ~/.config/hypr/scripts/wallpaper-import.sh <source_dir>
- Or bulk-copy only compatible 1080p/4k wallpapers from all sources:
  ~/.config/hypr/scripts/wallpaper-copy-from-sources.sh
SOURCES

echo
echo "Wallpaper sources ready under: $root"
echo "Next: import reviewed sets with wallpaper-import.sh"
