#!/usr/bin/env bash
# kage-project-rofi.sh — Wayle project chip cockpit (left-click handler)
set -euo pipefail

KAGE="${HOME}/.config/hypr/scripts/kage"
CACHE="${HOME}/.cache/kage/project-current.json"
ROFI_THEME="${HOME}/.config/rofi/actions.rasi"
rofi_theme_arg=(-theme "${ROFI_THEME}")
[ -f "${ROFI_THEME}" ] || rofi_theme_arg=()

notify() { notify-send -a kage "$1" "${2:-}" 2>/dev/null || true; }

# ── Build menu entries ────────────────────────────────────────────────────────

build_menu() {
  local header=""
  if [ -s "${CACHE}" ]; then
    local name branch framework dirty modified staged
    name="$(      jq -r '.name      // "?"' "${CACHE}" 2>/dev/null)"
    branch="$(    jq -r '.branch    // ""'  "${CACHE}" 2>/dev/null)"
    framework="$( jq -r '.framework // ""'  "${CACHE}" 2>/dev/null)"
    dirty="$(     jq -r '.dirty     // false' "${CACHE}" 2>/dev/null)"
    modified="$(  jq -r '.modified  // 0'   "${CACHE}" 2>/dev/null)"
    staged="$(    jq -r '.staged    // 0'   "${CACHE}" 2>/dev/null)"

    local status_str="clean"
    [ "$dirty" = "true" ] && status_str="✦${modified} ◆${staged}"

    header="  ${name}  [${framework}]  ${branch}  ${status_str}"

    # Project actions from cache
    jq -r '.actions[]? // empty' "${CACHE}" 2>/dev/null | while IFS= read -r act; do
      printf '⚡  %s\n' "$act"
    done
  fi

  # Always-available utility actions
  printf '  Refresh project\n'
  printf '  Open in terminal\n'
  printf '  Copy project path\n'
  printf '  Open file manager\n'
  printf '  Project status\n'
}

# ── Run rofi ─────────────────────────────────────────────────────────────────

MENU="$(build_menu)"

CHOICE="$(printf '%s\n' "${MENU}" | \
  rofi -dmenu -i -p '  Project' "${rofi_theme_arg[@]}" 2>/dev/null || true)"

[ -n "$CHOICE" ] || exit 0

# ── Dispatch ─────────────────────────────────────────────────────────────────

# Strip leading icon prefix for matching
CHOICE_CLEAN="$(printf '%s' "$CHOICE" | sed 's/^[[:space:]]*[⚡ ]*[[:space:]]*//')"

case "$CHOICE_CLEAN" in
  "Refresh project")
    "${KAGE}" project refresh
    ;;
  "Open in terminal")
    [ -s "${CACHE}" ] || exit 0
    _path="$(jq -r '.path // ""' "${CACHE}" 2>/dev/null)"
    [ -n "$_path" ] && [ -d "$_path" ] \
      && kitty --class noxflow-tool-large --title "terminal — $(basename "$_path")" -- \
           sh -lc "cd '${_path}'; exec \${SHELL:-zsh}" \
      || notify "Cannot open terminal" "Project path not found"
    ;;
  "Copy project path")
    [ -s "${CACHE}" ] || exit 0
    _path="$(jq -r '.path // ""' "${CACHE}" 2>/dev/null)"
    [ -n "$_path" ] \
      && printf '%s' "$_path" | wl-copy \
      && notify "Copied" "$_path" \
      || notify "Copy failed" "No project path cached"
    ;;
  "Open file manager")
    [ -s "${CACHE}" ] || exit 0
    _path="$(jq -r '.path // ""' "${CACHE}" 2>/dev/null)"
    if [ -n "$_path" ] && [ -d "$_path" ]; then
      xdg-open "$_path" >/dev/null 2>&1 &
    else
      notify "No path" "Project path not found"
    fi
    ;;
  "Project status")
    "${KAGE}" project status \
      | rofi -dmenu -p 'Project Status' "${rofi_theme_arg[@]}" >/dev/null 2>&1 || true
    ;;
  *)
    # It's a project action (e.g. "test", "build", "logs", etc.)
    if [ -n "$CHOICE_CLEAN" ]; then
      "${KAGE}" project action "${CHOICE_CLEAN}" &
    fi
    ;;
esac
