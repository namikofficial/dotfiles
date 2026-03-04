#!/usr/bin/env sh
set -eu

src="${1:-}"
default_wall="$HOME/.cache/wallpapers/fallback-4k.png"
dst="$HOME/.cache/lock-wallpaper"

if [ -z "$src" ]; then
  if [ -f "$HOME/.cache/current-wallpaper" ]; then
    src="$(cat "$HOME/.cache/current-wallpaper")"
  else
    src="$default_wall"
  fi
fi

if [ ! -f "$src" ]; then
  src="/usr/share/pixmaps/archlinux-logo.png"
fi

ln -sf "$src" "$dst"
