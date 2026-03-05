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

clone_or_update "aesthetic-wallpapers" "https://github.com/D3Ext/aesthetic-wallpapers.git"
clone_or_update "michaelscopic-wallpapers" "https://github.com/michaelScopic/Wallpapers.git"
clone_or_update "whoisyoges-lwalpapers" "https://github.com/whoisYoges/lwalpapers.git"
clone_or_update "minimalistic-collection" "https://github.com/DenverCoder1/minimalistic-wallpaper-collection.git"
clone_or_update "arch-minimal-wallpapers" "https://github.com/LagrangianLad/arch-minimal-wallpapers.git"
clone_or_update "archpapers" "https://github.com/connorslade/ArchPapers.git"
clone_or_update "nordic-wallpapers" "https://github.com/linuxdotexe/nordic-wallpapers.git"
clone_or_update "hyprland-wallpaper-bank" "https://github.com/JaKooLit/Wallpaper-Bank.git"
clone_or_update "mylinuxforwork-wallpaper" "https://github.com/mylinuxforwork/wallpaper.git"
clone_or_update "dharmx-walls" "https://github.com/dharmx/walls.git"
clone_or_update "linux-dynamic-wallpapers" "https://github.com/saint-13/Linux_Dynamic_Wallpapers.git"

cat > "$root/WEB_SOURCES.txt" <<'SOURCES'
Non-git wallpaper sources to browse manually:
- https://wall.alphacoders.com
- https://reddit.com/r/unixporn
- https://reddit.com/r/wallpaper
- https://wallhaven.cc

Tip:
- Review in source folders first.
- Import selected wallpapers to your rotating pool with:
  ~/.config/hypr/scripts/wallpaper-import.sh <source_dir>
SOURCES

echo
echo "Wallpaper sources ready under: $root"
echo "Next: import reviewed sets with wallpaper-import.sh"
