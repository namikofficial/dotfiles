#!/usr/bin/env bash
# Install the desktop UI typefaces: Onest (UI text) and Bricolage Grotesque
# (display headings). These are the NoxOrigin app's own type system
# (noxorigin/apps/app/package.json), so the desktop and the product share one
# identity. Neither is packaged for Arch, so this fetches the variable fonts
# from the official google/fonts repository, pinned to a commit and checked
# against SHA-256 before anything is installed. JetBrainsMono Nerd Font stays
# the monospace/icon font and comes from pacman.
set -euo pipefail

commit="bd8f81ddb5c74d5c8897b36ad88b440266245103"
base="https://raw.githubusercontent.com/google/fonts/$commit/ofl"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/noxflow"

# path-under-ofl  sha256  installed-name
fonts=(
  "onest/Onest%5Bwght%5D.ttf 966c5c29b4755da84b6854d5c21dd4eaa2420225d0e9874de602de176d4a9f31 Onest[wght].ttf"
  "bricolagegrotesque/BricolageGrotesque%5Bopsz%2Cwdth%2Cwght%5D.ttf 413e7357809ddd12fd80a96a8a396de0e401638d4acd3cb3e37532f0472ac682 BricolageGrotesque[opsz,wdth,wght].ttf"
  "onest/OFL.txt - OFL-Onest.txt"
  "bricolagegrotesque/OFL.txt - OFL-BricolageGrotesque.txt"
)

command -v curl >/dev/null 2>&1 || {
  echo "ERROR: curl is required" >&2
  exit 1
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$dest"

for entry in "${fonts[@]}"; do
  read -r path sum name <<<"$entry"
  curl -fsSL --retry 2 -o "$tmp/$name" "$base/$path"
  if [ "$sum" != "-" ]; then
    echo "$sum  $tmp/$name" | sha256sum -c --quiet - || {
      echo "ERROR: checksum mismatch for $name; not installing" >&2
      exit 1
    }
  fi
  install -m 0644 "$tmp/$name" "$dest/$name"
  printf 'installed %s\n' "$dest/$name"
done

fc-cache -f "$dest" >/dev/null
for family in "Onest" "Bricolage Grotesque"; do
  # No grep -q: it exits on the first match, fc-list gets SIGPIPE and
  # pipefail reports a failure. Family lists are comma-separated.
  fc-list : family | tr ',' '\n' | grep -x "$family" >/dev/null || {
    echo "ERROR: fontconfig does not see $family" >&2
    exit 1
  }
  printf 'fontconfig: %s ok\n' "$family"
done
