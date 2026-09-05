#!/usr/bin/env bash
# wallpaper-handpicked.sh — set up the handpicked wallpaper pool.
# No network access required; curation is manual.
#
# Usage:
#   ~/.config/hypr/scripts/wallpaper-add.sh <image-path>
#     adds one image; creates 4k copy + 1080p LANCZOS-downscaled copy
#
#   for f in ~/Downloads/wallpapers/*; do
#     ~/.config/hypr/scripts/wallpaper-add.sh "$f"
#   done
#
# Where to find good wallpapers (browse manually, then add with the script above):
#   https://wallhaven.cc/search?categories=110&purity=100&atleast=1920x1080&sorting=relevance&ai_art_filter=1
#   https://wallhaven.cc/search?categories=111&purity=100&atleast=1920x1080&sorting=relevance
#   https://wall.alphacoders.com/search.php?search=abstract
#   https://reddit.com/r/wallpaper
#   https://reddit.com/r/unixporn
#   https://reddit.com/r/AmoledBackgrounds
#   https://reddit.com/r/MinimalWallpaper

set -euo pipefail

pool="$HOME/Pictures/wallpaper/handpicked"
mkdir -p "$pool/1080p" "$pool/4k"

echo "Handpicked wallpaper pool is ready at:"
echo "  $pool/4k     ← drop your 4k+ images here directly"
echo "  $pool/1080p  ← 1080p variants are created automatically by wallpaper-add.sh"
echo
echo "To add images:"
echo "  ~/.config/hypr/scripts/wallpaper-add.sh <path-to-image>"
echo
echo "Rotation picks from:"
echo "  $pool/1080p : $pool/4k"
echo
echo "Current pool:"
count_4k=$(find "$pool/4k" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | wc -l)
count_1080p=$(find "$pool/1080p" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | wc -l)
echo "  4k:   $count_4k images"
echo "  1080p: $count_1080p images"
