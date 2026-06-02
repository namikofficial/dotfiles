#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"

check_link() {
  local target="$1"
  local source="$2"
  if [[ -L "$target" ]]; then
    local t s
    t="$(readlink -f "$target" || true)"
    s="$(readlink -f "$source" || true)"
    if [[ "$t" == "$s" ]]; then
      echo "OK    link $target"
    else
      echo "WARN  wrong link $target -> $t"
    fi
  elif [[ -e "$target" ]]; then
    echo "WARN  copy exists (not symlink): $target"
  else
    echo "WARN  missing target: $target"
  fi
}

check_copy_or_link() {
  local target="$1"
  local source="$2"
  if [[ -L "$target" ]]; then
    local t s
    t="$(readlink -f "$target" || true)"
    s="$(readlink -f "$source" || true)"
    if [[ "$t" == "$s" ]]; then
      echo "OK    link $target"
    else
      echo "WARN  wrong link $target -> $t"
    fi
    return
  fi

  if [[ ! -e "$target" ]]; then
    echo "WARN  missing target: $target"
    return
  fi

  if diff -qr "$target" "$source" >/dev/null 2>&1; then
    echo "OK    copy $target"
  else
    echo "WARN  copy differs from repo: $target"
  fi
}

check_link "$HOME/.config/hypr/hyprland.lua" "$ROOT_DIR/hypr/hyprland.lua"
check_link "$HOME/.config/hypr/lib" "$ROOT_DIR/hypr/lib"
check_link "$HOME/.config/hypr/monitor-layout.json" "$ROOT_DIR/hypr/monitor-layout.json"
check_link "$HOME/.config/uwsm/env" "$ROOT_DIR/uwsm/env"
check_link "$HOME/.config/uwsm/env-hyprland" "$ROOT_DIR/uwsm/env-hyprland"
check_link "$HOME/.config/rofi" "$ROOT_DIR/hypr/rofi"
check_copy_or_link "$HOME/.config/mimeapps.list" "$ROOT_DIR/mime/mimeapps.list"

if ! command -v jq >/dev/null 2>&1; then
  echo "WARN  jq is not installed"
fi

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty="$(git -C "$ROOT_DIR" status --short)"
  if [[ -n "$dirty" ]]; then
    echo "WARN  repo has uncommitted changes"
    echo "$dirty"
  else
    echo "OK    repo clean"
  fi
fi

if [[ -f /etc/modprobe.d/nvidia.conf ]]; then
  echo "INFO  system override exists: /etc/modprobe.d/nvidia.conf"
fi
if [[ -f /boot/loader/entries/arch-linux-igpu-safe.conf ]]; then
  echo "INFO  safe boot profile exists: /boot/loader/entries/arch-linux-igpu-safe.conf"
fi
if [[ -f /boot/loader/entries/arch-linux-zen.conf ]]; then
  echo "INFO  zen boot profile exists: /boot/loader/entries/arch-linux-zen.conf"
fi

if [[ -f "$ROOT_DIR/settings/state.local.json" ]]; then
  echo "INFO  local settings override present: settings/state.local.json"
else
  echo "INFO  local settings override missing: settings/state.local.json (optional)"
fi

if command -v hyprctl >/dev/null 2>&1; then
  provider=""
  if [[ -x "$ROOT_DIR/hypr/scripts/hypr-reload-safe.sh" ]]; then
    provider="$("$ROOT_DIR/hypr/scripts/hypr-reload-safe.sh" --probe 2>/dev/null || true)"
  fi
  if [[ -z "$provider" || "$provider" == "unknown" ]]; then
    provider="$(hyprctl systeminfo 2>/dev/null | awk -F': ' '/^configProvider:/ { print $2; exit }' || true)"
  fi
  if [[ "$provider" == "lua" ]]; then
    echo "OK    live Hyprland config provider is lua"
  elif [[ -n "$provider" ]]; then
    echo "WARN  live Hyprland config provider is $provider; restart Hyprland to activate hyprland.lua"
  fi
fi
