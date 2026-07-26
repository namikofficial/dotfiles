#!/usr/bin/env bash
set -euo pipefail

noxflow_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
}

noxflow_stop_if_running() {
  local file="$1"
  [ -f "$file" ] || return 1

  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$file"
    return 0
  fi

  rm -f "$file"
  return 1
}

noxflow_focused_cwd() {
  local pid
  pid="$(hyprctl -j activewindow 2>/dev/null | jq -r '.pid // empty' 2>/dev/null || true)"
  [ -n "$pid" ] || {
    printf '%s\n' "$HOME"
    return 0
  }
  readlink "/proc/${pid}/cwd" 2>/dev/null || printf '%s\n' "$HOME"
}

noxflow_git_root() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$1"
}
