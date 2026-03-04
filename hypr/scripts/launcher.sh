#!/usr/bin/env bash
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/launcher.rasi"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
PID_FILE="$STATE_DIR/rofi-launcher.pid"
OTHER_PID_FILE="$STATE_DIR/rofi-actions.pid"
CACHE_FILE="$STATE_DIR/launcher-apps.tsv"

mkdir -p "$STATE_DIR"

stop_if_running() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$pid_file"
    return 0
  fi
  rm -f "$pid_file"
  return 1
}

# Same key toggles the menu closed.
if stop_if_running "$PID_FILE"; then
  exit 0
fi

# If quick-actions is open, close it before showing launcher.
stop_if_running "$OTHER_PID_FILE" || true

parse_desktop_entry() {
  local file="$1"
  awk '
    BEGIN {
      in_entry = 0
      name = ""
      icon = ""
      nodisplay = ""
      hidden = ""
    }
    /^\[Desktop Entry\]$/ {
      in_entry = 1
      next
    }
    /^\[/ {
      if (in_entry) {
        exit
      }
    }
    !in_entry {
      next
    }
    /^Name=/ && name == "" {
      sub(/^Name=/, "", $0)
      name = $0
      next
    }
    /^Icon=/ && icon == "" {
      sub(/^Icon=/, "", $0)
      icon = $0
      next
    }
    /^NoDisplay=/ {
      sub(/^NoDisplay=/, "", $0)
      nodisplay = tolower($0)
      next
    }
    /^Hidden=/ {
      sub(/^Hidden=/, "", $0)
      hidden = tolower($0)
      next
    }
    END {
      if (name == "" || nodisplay == "true" || hidden == "true") {
        exit
      }
      gsub(/\t/, " ", name)
      gsub(/\r/, "", name)
      gsub(/\t/, " ", icon)
      gsub(/\r/, "", icon)
      printf "%s\t%s\n", name, icon
    }
  ' "$file"
}

build_cache() {
  : > "$CACHE_FILE"
  declare -A seen_ids=()
  local desktop_file desktop_id parsed name icon

  for desktop_file in \
    "$HOME/.local/share/applications"/*.desktop \
    /usr/local/share/applications/*.desktop \
    /usr/share/applications/*.desktop; do
    [ -f "$desktop_file" ] || continue
    desktop_id="$(basename "$desktop_file")"
    if [ -n "${seen_ids[$desktop_id]:-}" ]; then
      continue
    fi
    parsed="$(parse_desktop_entry "$desktop_file" || true)"
    [ -n "$parsed" ] || continue
    IFS=$'\t' read -r name icon <<< "$parsed"
    printf '%s\t%s\t%s\n' "$name" "$desktop_id" "$icon" >> "$CACHE_FILE"
    seen_ids["$desktop_id"]=1
  done

  sort -f -t $'\t' -k1,1 "$CACHE_FILE" -o "$CACHE_FILE"
}

emit_menu_rows() {
  local name desktop_id icon
  local display_name hint idx=0

  while IFS=$'\t' read -r name desktop_id icon; do
    display_name="$name"
    if [ "${#display_name}" -gt 46 ]; then
      display_name="${display_name:0:43}..."
    fi

    case "$idx" in
      0) hint='Ctrl+1' ;;
      1) hint='Ctrl+2' ;;
      2) hint='Ctrl+3' ;;
      3) hint='Ctrl+4' ;;
      4) hint='Ctrl+5' ;;
      5) hint='Ctrl+6' ;;
      6) hint='Ctrl+7' ;;
      7) hint='Ctrl+8' ;;
      8) hint='Ctrl+9' ;;
      9) hint='Ctrl+0' ;;
      *) hint='Ctrl+1..0' ;;
    esac

    if [ -n "$icon" ]; then
      printf '%s\t%s\0icon\x1f%s\n' "$display_name" "$hint" "$icon"
    else
      printf '%s\t%s\n' "$display_name" "$hint"
    fi
    idx=$((idx + 1))
  done < "$CACHE_FILE"
}

build_cache
[ -s "$CACHE_FILE" ] || exit 0

set +e
selection="$(
  emit_menu_rows | rofi \
    -dmenu \
    -i \
    -show-icons \
    -display-columns 1,2 \
    -display-column-separator '\t' \
    -kb-select-1 'Control+1,Super+1' \
    -kb-select-2 'Control+2,Super+2' \
    -kb-select-3 'Control+3,Super+3' \
    -kb-select-4 'Control+4,Super+4' \
    -kb-select-5 'Control+5,Super+5' \
    -kb-select-6 'Control+6,Super+6' \
    -kb-select-7 'Control+7,Super+7' \
    -kb-select-8 'Control+8,Super+8' \
    -kb-select-9 'Control+9,Super+9' \
    -kb-select-10 'Control+0,Super+0' \
    -kb-cancel 'Escape,Control+g,Super+space' \
    -p 'Apps' \
    -mesg 'Quick launch with Ctrl+1..0 (or Enter)' \
    -format 'i' \
    -theme "$ROFI_THEME" \
    -pid "$PID_FILE"
)"
rofi_status=$?
set -e
rm -f "$PID_FILE"
[ "$rofi_status" -eq 0 ] || exit 0
[ -n "$selection" ] || exit 0

mapfile -t app_rows < "$CACHE_FILE"

launch_one() {
  local row_index="$1"
  local row desktop_id
  row="${app_rows[$row_index]:-}"
  [ -n "$row" ] || return 0
  IFS=$'\t' read -r _ desktop_id _ <<< "$row"
  [ -n "$desktop_id" ] || return 0
  if command -v gtk-launch >/dev/null 2>&1; then
    gtk-launch "$desktop_id" >/dev/null 2>&1 &
  else
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -a Launcher "gtk-launch missing" "Install gtk3 to launch desktop entries."
    fi
  fi
}

case "$selection" in
  *[!0-9]*) exit 0 ;;
esac

launch_one "$selection"
