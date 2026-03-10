#!/usr/bin/env bash
set -euo pipefail

WITH_HYPRSPACE=0
PLUGIN_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/plugins"
SRC_DIR="$PLUGIN_ROOT/src/hyprland-plugins"
OUT_DIR="$PLUGIN_ROOT/hyprexpo"
OUT_SO="$OUT_DIR/hyprexpo.so"

usage() {
  echo "Usage: $0 [--with-hyprspace]" >&2
}

for arg in "$@"; do
  case "$arg" in
    --with-hyprspace) WITH_HYPRSPACE=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

loaded_hyprexpo_path() {
  hypr_pid="$(pgrep -x Hyprland 2>/dev/null | head -n1 || true)"
  [ -n "$hypr_pid" ] || return 1
  awk '/\/.*hyprexpo\.so$/ { print $NF; exit }' "/proc/$hypr_pid/maps" 2>/dev/null
}

clone_or_update_repo() {
  mkdir -p "$(dirname "$SRC_DIR")" "$OUT_DIR"
  if [[ -d "$SRC_DIR/.git" ]]; then
    git -C "$SRC_DIR" fetch --depth 1 origin HEAD
    git -C "$SRC_DIR" reset --hard FETCH_HEAD
  else
    git clone --depth 1 https://github.com/hyprwm/hyprland-plugins "$SRC_DIR"
  fi
}

build_hyprexpo() {
  require_cmd git
  require_cmd make
  require_cmd g++
  require_cmd pkg-config

  clone_or_update_repo
  make -C "$SRC_DIR/hyprexpo" clean >/dev/null 2>&1 || true
  make -C "$SRC_DIR/hyprexpo" all
  install -Dm755 "$SRC_DIR/hyprexpo/hyprexpo.so" "$OUT_SO"
}

load_hyprexpo_if_possible() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  current_hyprexpo="$(loaded_hyprexpo_path || true)"
  if [[ -n "$current_hyprexpo" && "$current_hyprexpo" != "$OUT_SO" ]]; then
    hyprctl plugin unload "$current_hyprexpo" >/dev/null 2>&1 || true
    sleep 1
  fi
  if [[ "$current_hyprexpo" == "$OUT_SO" ]] && hyprctl plugin list 2>/dev/null | grep -q 'Plugin hyprexpo'; then
    return 0
  fi
  hyprctl plugin load "$OUT_SO" >/dev/null 2>&1 || true
}

build_hyprexpo
load_hyprexpo_if_possible

if (( WITH_HYPRSPACE )); then
  echo "warning: Hyprspace is not auto-installed in the direct-build path." >&2
  echo "warning: use hyprpm manually if you want to experiment with it." >&2
fi

echo "HyprExpo installed at: $OUT_SO"
