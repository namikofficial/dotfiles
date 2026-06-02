#!/usr/bin/env bash
set -euo pipefail

config="${1:-$HOME/.config/hypr/hyprland.lua}"

if [ ! -f "$config" ]; then
  echo "Hyprland config not found: $config" >&2
  exit 1
fi

validate_lua_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  luac -p "$file"
}

case "$config" in
  *.lua)
    if ! command -v luac >/dev/null 2>&1; then
      echo "luac not found" >&2
      exit 1
    fi

    config_dir="$(CDPATH='' cd -- "$(dirname -- "$config")" && pwd)"
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"

    validate_lua_file "$config"
    for file in "$config_dir"/lib/*.lua "$config_dir"/conf/*.lua; do
      [ -f "$file" ] || continue
      validate_lua_file "$file"
    done
    validate_lua_file "$cache_dir/theme-colors-hyprland.lua"
    validate_lua_file "$cache_dir/settings.generated.lua"
    ;;
  *)
    if ! command -v Hyprland >/dev/null 2>&1; then
      echo "Hyprland not found" >&2
      exit 1
    fi
    Hyprland --verify-config -c "$config"
    ;;
esac

echo "Hyprland config OK: $config"
