#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
MIMEAPPS="$CONFIG_DIR/mimeapps.list"
ARK_DESKTOP="org.kde.ark.desktop"
DOLPHIN_DESKTOP="org.kde.dolphin.desktop"

desktop_entry_exists() {
  local desktop="$1"
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  local dir

  [[ -f "$data_home/applications/$desktop" ]] && return 0
  while IFS= read -r dir; do
    [[ -f "$dir/applications/$desktop" ]] && return 0
  done < <(tr ':' '\n' <<<"$data_dirs")
  return 1
}

if ! command -v xdg-mime >/dev/null 2>&1; then
  echo "xdg-mime is required to configure file associations." >&2
  exit 1
fi

if ! desktop_entry_exists "$DOLPHIN_DESKTOP"; then
  echo "Dolphin desktop entry is missing: $DOLPHIN_DESKTOP" >&2
  exit 1
fi

if ! desktop_entry_exists "$ARK_DESKTOP"; then
  echo "Ark desktop entry is missing: $ARK_DESKTOP" >&2
  echo "Install it with: sudo pacman -S --needed ark 7zip unrar" >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"

archive_mimes=(
  application/zip
  application/vnd.rar
  application/x-rar
  application/x-7z-compressed
  application/x-tar
  application/gzip
  application/x-bzip2
  application/x-xz
  application/x-compressed-tar
  application/x-bzip2-compressed-tar
  application/x-xz-compressed-tar
)

xdg-mime default "$DOLPHIN_DESKTOP" inode/directory
for mime in "${archive_mimes[@]}"; do
  xdg-mime default "$ARK_DESKTOP" "$mime"
done

if [[ ! -f "$MIMEAPPS" ]]; then
  touch "$MIMEAPPS"
fi

tmp="$(mktemp)"
awk '
  BEGIN {
    section = ""
    inserted = 0
  }
  /^\[/ {
    if (section == "[Removed Associations]" && !inserted) {
      print "application/zip=org.prismlauncher.PrismLauncher.desktop;"
      inserted = 1
    }
    section = $0
  }
  section == "[Removed Associations]" && /^application\/zip=/ {
    value = substr($0, index($0, "=") + 1)
    if (index(";" value ";", ";org.prismlauncher.PrismLauncher.desktop;") == 0) {
      if (value == "") {
        $0 = "application/zip=org.prismlauncher.PrismLauncher.desktop;"
      } else {
        $0 = $0 ";org.prismlauncher.PrismLauncher.desktop;"
      }
    }
    inserted = 1
  }
  { print }
  END {
    if (section == "[Removed Associations]" && !inserted) {
      print "application/zip=org.prismlauncher.PrismLauncher.desktop;"
    } else if (inserted == 0) {
      print ""
      print "[Removed Associations]"
      print "application/zip=org.prismlauncher.PrismLauncher.desktop;"
    }
  }
' "$MIMEAPPS" >"$tmp"
mv "$tmp" "$MIMEAPPS"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
if command -v update-desktop-database >/dev/null 2>&1 && [[ -d "$data_home/applications" ]]; then
  update-desktop-database "$data_home/applications" >/dev/null 2>&1 || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

echo "Folder default: $(xdg-mime query default inode/directory)"
for mime in application/zip application/vnd.rar application/x-7z-compressed application/x-tar; do
  echo "$mime: $(xdg-mime query default "$mime")"
done
