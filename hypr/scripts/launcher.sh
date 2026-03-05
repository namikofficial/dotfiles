#!/usr/bin/env bash
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/launcher.rasi"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
PID_FILE="$STATE_DIR/rofi-launcher.pid"
OTHER_PID_FILE="$STATE_DIR/rofi-actions.pid"
CACHE_FILE="$STATE_DIR/launcher-apps.tsv"
ORDERED_CACHE="$STATE_DIR/launcher-ordered.tsv"
USAGE_FILE="$STATE_DIR/launcher-usage.tsv"

MODE="${1:-frequent}"
if [ "$MODE" != "frequent" ] && [ "$MODE" != "all" ]; then
  MODE="frequent"
fi

TOP_COUNT=0

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

rebuild_ordered_cache() {
  local row name desktop_id icon
  local -a base_rows=()
  local -a ordered_rows=()
  declare -A row_by_id=()
  declare -A added=()

  mapfile -t base_rows < "$CACHE_FILE"
  [ "${#base_rows[@]}" -gt 0 ] || return 0

  for row in "${base_rows[@]}"; do
    IFS=$'\t' read -r name desktop_id icon <<< "$row"
    row_by_id["$desktop_id"]="$row"
  done

  TOP_COUNT=0
  if [ "$MODE" = "frequent" ] && [ -s "$USAGE_FILE" ]; then
    while IFS=$'\t' read -r desktop_id _count; do
      [ -n "${desktop_id:-}" ] || continue
      row="${row_by_id[$desktop_id]:-}"
      [ -n "$row" ] || continue
      if [ -n "${added[$desktop_id]:-}" ]; then
        continue
      fi
      ordered_rows+=("$row")
      added["$desktop_id"]=1
      TOP_COUNT=$((TOP_COUNT + 1))
      [ "$TOP_COUNT" -ge 5 ] && break
    done < <(sort -t $'\t' -k2,2nr "$USAGE_FILE" 2>/dev/null || true)
  fi

  for row in "${base_rows[@]}"; do
    IFS=$'\t' read -r _name desktop_id _icon <<< "$row"
    [ -n "${added[$desktop_id]:-}" ] && continue
    ordered_rows+=("$row")
    added["$desktop_id"]=1
  done

  : > "$ORDERED_CACHE"
  for row in "${ordered_rows[@]}"; do
    printf '%s\n' "$row" >> "$ORDERED_CACHE"
  done
}

hint_for_index() {
  case "$1" in
    0) echo 'Ctrl+1' ;;
    1) echo 'Ctrl+2' ;;
    2) echo 'Ctrl+3' ;;
    3) echo 'Ctrl+4' ;;
    4) echo 'Ctrl+5' ;;
    5) echo 'Ctrl+6' ;;
    6) echo 'Ctrl+7' ;;
    7) echo 'Ctrl+8' ;;
    8) echo 'Ctrl+9' ;;
    9) echo 'Ctrl+0' ;;
    *) echo '--' ;;
  esac
}

emit_menu_rows() {
  local name desktop_id icon
  local display_name hint idx=0
  local max_name=0
  local name_width=44

  while IFS=$'\t' read -r name desktop_id icon; do
    display_name="$name"
    if [ "$idx" -lt "$TOP_COUNT" ]; then
      display_name="[top] ${display_name}"
    fi
    if [ "${#display_name}" -gt 46 ]; then
      display_name="${display_name:0:43}..."
    fi
    if [ "${#display_name}" -gt "$max_name" ]; then
      max_name="${#display_name}"
    fi
    idx=$((idx + 1))
  done < "$ORDERED_CACHE"

  if [ "$max_name" -gt 34 ]; then
    name_width="$max_name"
  fi
  if [ "$name_width" -gt 56 ]; then
    name_width=56
  fi

  idx=0
  while IFS=$'\t' read -r name desktop_id icon; do
    display_name="$name"
    if [ "$idx" -lt "$TOP_COUNT" ]; then
      display_name="[top] ${display_name}"
    fi
    if [ "${#display_name}" -gt 46 ]; then
      display_name="${display_name:0:43}..."
    fi
    hint="$(hint_for_index "$idx")"

    printf -v display_name '%-*s' "$name_width" "$display_name"
    if [ -n "$icon" ]; then
      printf '%s | quick | %7s\0icon\x1f%s\n' "$display_name" "$hint" "$icon"
    else
      printf '%s | quick | %7s\n' "$display_name" "$hint"
    fi
    idx=$((idx + 1))
  done < "$ORDERED_CACHE"
}

menu_message() {
  if [ "$MODE" = "all" ]; then
    echo 'All apps | Ctrl+Tab top-5 view | type to search'
  else
    echo 'Top 5 first | Ctrl+Tab all apps | type to search'
  fi
}

build_cache
[ -s "$CACHE_FILE" ] || exit 0
rebuild_ordered_cache
[ -s "$ORDERED_CACHE" ] || exit 0

set +e
selection="$(
  emit_menu_rows | rofi \
    -dmenu \
    -i \
    -show-icons \
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
    -kb-custom-1 'Control+Tab' \
    -kb-cancel 'Escape,Control+g,Super+space' \
    -p 'Apps' \
    -mesg "$(menu_message)" \
    -format 'i' \
    -theme "$ROFI_THEME" \
    -pid "$PID_FILE"
)"
rofi_status=$?
set -e
rm -f "$PID_FILE"

if [ "$rofi_status" -eq 10 ]; then
  if [ "$MODE" = "all" ]; then
    exec "$0" frequent
  else
    exec "$0" all
  fi
fi

[ "$rofi_status" -eq 0 ] || exit 0
[ -n "$selection" ] || exit 0

mapfile -t app_rows < "$ORDERED_CACHE"

update_usage() {
  local desktop_id="$1"
  local tmp_file="$USAGE_FILE.tmp.$$"

  if [ -f "$USAGE_FILE" ]; then
    awk -F '\t' -v id="$desktop_id" '
      BEGIN { found = 0 }
      NF >= 2 {
        if ($1 == id) {
          $2 = $2 + 1
          found = 1
        }
        print $1 "\t" $2
        next
      }
      END {
        if (!found) {
          print id "\t1"
        }
      }
    ' "$USAGE_FILE" > "$tmp_file"
  else
    printf '%s\t1\n' "$desktop_id" > "$tmp_file"
  fi

  sort -t $'\t' -k2,2nr "$tmp_file" | awk -F '\t' '!seen[$1]++' > "$USAGE_FILE"
  rm -f "$tmp_file"
}

launch_one() {
  local row_index="$1"
  local row desktop_id
  row="${app_rows[$row_index]:-}"
  [ -n "$row" ] || return 0
  IFS=$'\t' read -r _ desktop_id _ <<< "$row"
  [ -n "$desktop_id" ] || return 0
  if command -v gtk-launch >/dev/null 2>&1; then
    gtk-launch "$desktop_id" >/dev/null 2>&1 &
    update_usage "$desktop_id"
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
