#!/usr/bin/env sh
set -eu

detect_provider() {
  # Prefer live bind introspection because systeminfo can lag/misreport during
  # migration windows while Lua binds are already active.
  if command -v jq >/dev/null 2>&1; then
    if hyprctl binds -j 2>/dev/null | jq -e '.[] | select(.dispatcher=="__lua")' >/dev/null 2>&1; then
      printf '%s\n' "lua"
      return 0
    fi
  fi

  provider="$(hyprctl systeminfo 2>/dev/null | awk -F': ' '/^configProvider:/ { print $2; exit }' || true)"
  case "$provider" in
    lua|hyprlang)
      printf '%s\n' "$provider"
      return 0
      ;;
  esac
  printf '%s\n' "unknown"
}

provider="$(detect_provider)"

if [ "${1:-}" = "--probe" ]; then
  printf '%s\n' "$provider"
  exit 0
fi

case "$provider" in
  lua)
    hyprctl reload
    ;;
  hyprlang)
    echo "Hyprland is running with legacy hyprlang config. Restart the Hyprland/login session to activate hyprland.lua." >&2
    exit 2
    ;;
  *)
    echo "Could not determine Hyprland config provider." >&2
    exit 1
    ;;
esac
