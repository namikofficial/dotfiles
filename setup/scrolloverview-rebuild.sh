#!/usr/bin/env bash
set -euo pipefail

# Rebuild the hyprland-scroll-overview plugin after a Hyprland upgrade.
# ABI-breaking: the plugin must match the exact installed Hyprland version.
#
# Usage:
#   setup/scrolloverview-rebuild.sh          # rebuild + enable via hyprpm
#   setup/scrolloverview-rebuild.sh --source # force a source build
#
# After a successful rebuild, the overview is enabled immediately (hyprpm
# path) or loaded into the running session (source path).

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_repo="https://github.com/yayuuu/hyprland-scroll-overview.git"
build_dir="${XDG_RUNTIME_DIR:-/tmp}/scrolloverview-build"
mode="${1:-hyprpm}"

say() { printf '[scrolloverview] %s\n' "$*"; }

# Verify Hyprland is running and report its version for the rebuild.
hypr_version() {
  hyprctl version 2>/dev/null | head -n1 || true
}

rebuild_hyprpm() {
  say "rebuilding via hyprpm (Hyprland: $(hypr_version))"
  if ! command -v hyprpm >/dev/null 2>&1; then
    echo "scrolloverview-rebuild: hyprpm is not installed" >&2
    return 1
  fi

  # Known pitfall: the FIRST `hyprpm update` needs sudo (header install) and
  # writes the state store to /var/cache/hyprpm/<user> as root. Every later
  # non-root `hyprpm add` then fails "Headers outdated" against the root-owned
  # store. If that error appears, clear the stale store and start fresh:
  #   sudo rm -rf /var/cache/hyprpm/<user>   # where <user> = $(whoami)
  local add_out
  add_out="$(hyprpm add "$plugin_repo" 2>&1 || true)"
  if ! printf '%s\n' "$add_out" | grep -q 'Plugin repository added\|already'; then
    if printf '%s\n' "$add_out" | grep -q 'Headers outdated'; then
      echo "scrolloverview-rebuild: hyprpm state store is root-owned from an earlier sudo run." >&2
      echo "Fix: sudo rm -rf /var/cache/hyprpm/$(whoami) && $0" >&2
    else
      printf 'scrolloverview-rebuild: hyprpm add failed:\n%s\n' "$add_out" >&2
    fi
    return 1
  fi

  hyprpm update
  hyprpm enable scrolloverview
  say "hyprpm rebuild complete"
}

rebuild_source() {
  say "source build (Hyprland: $(hypr_version))"
  local flags=(-DCMAKE_BUILD_TYPE=Release)
  # CMake option name varies by plugin version; try both.
  if [[ "${SCROLL_OVERVIEW_USE_SYSTEM_HEADERS:-0}" == "1" ]]; then
    flags+=(-DNO_SYSTEM_HEADERS=OFF)
  fi

  rm -rf "$build_dir"
  git clone --depth=1 "$plugin_repo" "$build_dir"
  cmake -S "$build_dir" -B "$build_dir/build" "${flags[@]}"
  cmake --build "$build_dir/build" -j"$(nproc)"

  local so
  so="$(find "$build_dir/build" -name '*.so' | head -n1)"
  if [[ -z "$so" ]]; then
    echo "scrolloverview-rebuild: no .so produced" >&2
    return 1
  fi

  # Persist the plugin path for next-session loading.
  mkdir -p "$HOME/.config/hypr/plugins"
  cp "$so" "$HOME/.config/hypr/plugins/libscrolloverview.so"
  say "installed $so"

  # Load into the running session if Hyprland is up.
  if hyprctl plugin list 2>/dev/null | grep -qi 'scrolloverview'; then
    hyprctl plugin unload "$HOME/.config/hypr/plugins/libscrolloverview.so" >/dev/null 2>&1 || true
  fi
  hyprctl plugin load "$HOME/.config/hypr/plugins/libscrolloverview.so" 2>/dev/null || true
  say "source build complete"
}

case "$mode" in
  hyprpm) rebuild_hyprpm ;;
  --source) rebuild_source ;;
  *)
    echo "usage: $0 [hyprpm|--source]" >&2
    exit 2
    ;;
esac
