#!/usr/bin/env sh
set -eu

notes_dir="${NOXFLOW_NOTES_DIR:-$HOME/Documents/notes}"
mkdir -p "$notes_dir"

if command -v code >/dev/null 2>&1; then
  code "$notes_dir" >/dev/null 2>&1 &
  exit 0
fi

if command -v codium >/dev/null 2>&1; then
  codium "$notes_dir" >/dev/null 2>&1 &
  exit 0
fi

if command -v obsidian >/dev/null 2>&1; then
  obsidian "$notes_dir" >/dev/null 2>&1 &
  exit 0
fi

if [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1; then
  "$TERMINAL" -e sh -lc "cd \"$notes_dir\"; exec ${EDITOR:-nvim}" >/dev/null 2>&1 &
  exit 0
fi

if command -v dolphin >/dev/null 2>&1; then
  dolphin "$notes_dir" >/dev/null 2>&1 &
  exit 0
fi

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$notes_dir" >/dev/null 2>&1 &
fi
