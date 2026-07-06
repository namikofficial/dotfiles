#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

mode="${1:-launch}"
start_ai=0
focus_sidecar=1

while (($#)); do
  case "$1" in
    --ai|--start-ai)
      start_ai=1
      ;;
    --no-sidecar)
      focus_sidecar=0
      ;;
    launch|restore)
      mode="$1"
      ;;
  esac
  shift || true
done

cwd="$(noxflow_focused_cwd)"
root="$(noxflow_git_root "$cwd")"
session="$(basename "$root" | tr -cs '[:alnum:]' '-')"
[ -n "$session" ] || session="project"

open_editor() {
  if command -v code >/dev/null 2>&1; then
    code "$root" >/dev/null 2>&1 &
    return 0
  fi
  if command -v nvim >/dev/null 2>&1 && command -v kitty >/dev/null 2>&1; then
    kitty --title "$session-editor" -e bash -lc "cd '$root' && exec nvim" >/dev/null 2>&1 &
    return 0
  fi
}

start_tmux() {
  if command -v kitty >/dev/null 2>&1; then
    kitty --title "$session" -e tmux new-session -A -s "$session" -c "$root" >/dev/null 2>&1 &
    return 0
  fi
  tmux new-session -A -s "$session" -c "$root"
}

restore_sidecar() {
  if [ "$focus_sidecar" -eq 1 ] && [ -x "$SCRIPT_DIR/sidepanel.sh" ]; then
    "$SCRIPT_DIR/sidepanel.sh" restore-all >/dev/null 2>&1 || true
  fi
}

start_optional_ai() {
  [ "$start_ai" -eq 1 ] || return 0
  if command -v local-ai-runtime >/dev/null 2>&1; then
    local-ai-runtime start >/dev/null 2>&1 || true
  fi
  if [ -x "$SCRIPT_DIR/scratchpad-manager.sh" ]; then
    "$SCRIPT_DIR/scratchpad-manager.sh" launch ai >/dev/null 2>&1 || true
  fi
}

case "$mode" in
  launch|restore)
    open_editor
    start_tmux
    restore_sidecar
    start_optional_ai
    ;;
  *)
    echo "usage: $0 [launch|restore] [--ai] [--no-sidecar]" >&2
    exit 2
    ;;
esac

