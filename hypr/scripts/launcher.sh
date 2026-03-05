#!/usr/bin/env bash
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/launcher.rasi"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
PID_FILE="$STATE_DIR/rofi-launcher.pid"
OTHER_PID_FILE="$STATE_DIR/rofi-actions.pid"
CACHE_FILE="$STATE_DIR/launcher-apps.tsv"
USAGE_FILE="$STATE_DIR/launcher-usage.tsv"
CACHE_REFRESH_PID_FILE="$STATE_DIR/launcher-cache-refresh.pid"
CACHE_TTL_SECONDS="${LAUNCHER_CACHE_TTL_SECONDS:-21600}"
ROWS_ALL_FILE="$STATE_DIR/launcher-rows-all.txt"
ROWS_FREQUENT_FILE="$STATE_DIR/launcher-rows-frequent.txt"

mkdir -p "$STATE_DIR"

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
  local tmp_file="${CACHE_FILE}.tmp.$$"
  : > "$tmp_file"
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
    printf '%s\t%s\t%s\n' "$name" "$desktop_id" "$icon" >> "$tmp_file"
    seen_ids["$desktop_id"]=1
  done

  sort -f -t $'\t' -k1,1 "$tmp_file" -o "$tmp_file"
  mv "$tmp_file" "$CACHE_FILE"
}

file_mtime_epoch() {
  local file="$1"
  stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0
}

cache_is_fresh() {
  [ -s "$CACHE_FILE" ] || return 1
  local now mtime age
  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$CACHE_FILE")"
  age=$((now - mtime))
  [ "$age" -lt "$CACHE_TTL_SECONDS" ]
}

schedule_cache_refresh() {
  local pid
  if [ -f "$CACHE_REFRESH_PID_FILE" ]; then
    pid="$(cat "$CACHE_REFRESH_PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$CACHE_REFRESH_PID_FILE"
  fi

  "$0" --rebuild-cache >/dev/null 2>&1 &
  echo "$!" > "$CACHE_REFRESH_PID_FILE"
}

ensure_cache() {
  if cache_is_fresh; then
    return 0
  fi

  if [ -s "$CACHE_FILE" ]; then
    # Use stale cache immediately and refresh in the background.
    schedule_cache_refresh
    return 0
  fi

  build_cache
}

build_rows_cache() {
  local tmp_all="${ROWS_ALL_FILE}.tmp.$$"
  local tmp_frequent="${ROWS_FREQUENT_FILE}.tmp.$$"

  emit_rows_all > "$tmp_all"
  emit_rows_frequent > "$tmp_frequent"

  mv "$tmp_all" "$ROWS_ALL_FILE"
  mv "$tmp_frequent" "$ROWS_FREQUENT_FILE"
}

ensure_data_cache() {
  ensure_cache
  [ -s "$CACHE_FILE" ] || return 1

  if [ ! -s "$ROWS_ALL_FILE" ] || [ ! -s "$ROWS_FREQUENT_FILE" ]; then
    build_rows_cache
  fi
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

emit_rows_all() {
  local idx=0 name desktop_id icon display hint

  while IFS=$'\t' read -r name desktop_id icon; do
    display="$name"
    [ "${#display}" -gt 46 ] && display="${display:0:43}..."
    hint="$(hint_for_index "$idx")"

    if [ -n "$icon" ]; then
      printf '%s | quick | %7s\0icon\x1f%s\x1finfo\x1f%s\n' "$display" "$hint" "$icon" "$desktop_id"
    else
      printf '%s | quick | %7s\0info\x1f%s\n' "$display" "$hint" "$desktop_id"
    fi
    idx=$((idx + 1))
  done < "$CACHE_FILE"
}

emit_rows_frequent() {
  local -a rows=()
  local -a fallback_rows=()
  local row name desktop_id icon idx=0
  declare -A row_by_id=()
  declare -A added=()

  mapfile -t fallback_rows < "$CACHE_FILE"
  [ "${#fallback_rows[@]}" -gt 0 ] || return 0

  for row in "${fallback_rows[@]}"; do
    IFS=$'\t' read -r name desktop_id icon <<< "$row"
    row_by_id["$desktop_id"]="$row"
  done

  if [ -s "$USAGE_FILE" ]; then
    while IFS=$'\t' read -r desktop_id _count; do
      [ -n "${desktop_id:-}" ] || continue
      row="${row_by_id[$desktop_id]:-}"
      [ -n "$row" ] || continue
      [ -n "${added[$desktop_id]:-}" ] && continue
      rows+=("$row")
      added["$desktop_id"]=1
      [ "${#rows[@]}" -ge 5 ] && break
    done < <(sort -t $'\t' -k2,2nr "$USAGE_FILE" 2>/dev/null || true)
  fi

  if [ "${#rows[@]}" -lt 5 ]; then
    for row in "${fallback_rows[@]}"; do
      IFS=$'\t' read -r _name desktop_id _icon <<< "$row"
      [ -n "${added[$desktop_id]:-}" ] && continue
      rows+=("$row")
      added["$desktop_id"]=1
      [ "${#rows[@]}" -ge 5 ] && break
    done
  fi

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name desktop_id icon <<< "$row"
    display="[top] $name"
    [ "${#display}" -gt 46 ] && display="${display:0:43}..."
    hint="$(hint_for_index "$idx")"

    if [ -n "$icon" ]; then
      printf '%s | quick | %7s\0icon\x1f%s\x1finfo\x1f%s\n' "$display" "$hint" "$icon" "$desktop_id"
    else
      printf '%s | quick | %7s\0info\x1f%s\n' "$display" "$hint" "$desktop_id"
    fi
    idx=$((idx + 1))
  done
}

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

launch_desktop_id() {
  local desktop_id="$1"
  [ -n "$desktop_id" ] || return 0

  if command -v gtk-launch >/dev/null 2>&1; then
    gtk-launch "$desktop_id" >/dev/null 2>&1 &
    update_usage "$desktop_id"
    "$0" --rebuild-rows >/dev/null 2>&1 &
  else
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -a Launcher "gtk-launch missing" "Install gtk3 to launch desktop entries."
    fi
  fi
}

resolve_selection_to_id() {
  local selected_text="${1:-}"
  local desktop_id="${ROFI_INFO:-}"

  if [ -n "$desktop_id" ]; then
    printf '%s\n' "$desktop_id"
    return 0
  fi

  selected_text="${selected_text%%|*}"
  selected_text="${selected_text#\[top\] }"
  selected_text="$(printf '%s' "$selected_text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  awk -F '\t' -v name="$selected_text" '$1 == name { print $2; exit }' "$CACHE_FILE"
}

handle_script_mode() {
  local mode="$1"
  local selected="${2:-}"
  local retv="${ROFI_RETV:-0}"

  ensure_data_cache
  [ -s "$CACHE_FILE" ] || exit 0

  case "$retv" in
    0)
      if [ "$mode" = "all" ]; then
        cat "$ROWS_ALL_FILE"
      else
        cat "$ROWS_FREQUENT_FILE"
      fi
      ;;
    *)
      desktop_id="$(resolve_selection_to_id "$selected")"
      [ -n "$desktop_id" ] || exit 0
      launch_desktop_id "$desktop_id"
      ;;
  esac
}

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

# Cache maintenance entrypoints.
if [ "${1:-}" = "--rebuild-cache" ]; then
  build_cache
  build_rows_cache
  rm -f "$CACHE_REFRESH_PID_FILE"
  exit 0
fi

if [ "${1:-}" = "--rebuild-rows" ]; then
  ensure_cache
  build_rows_cache
  exit 0
fi

if [ "${1:-}" = "--warm-cache" ]; then
  ensure_data_cache
  exit 0
fi

# Script mode entrypoint for rofi tabs.
if [ "${1:-}" = "--mode" ]; then
  mode="${2:-frequent}"
  selected="${3:-}"
  if [ "$mode" != "all" ]; then
    mode="frequent"
  fi
  handle_script_mode "$mode" "$selected"
  exit 0
fi

# Launcher entrypoint (bound to Super+Space).
if stop_if_running "$PID_FILE"; then
  exit 0
fi

stop_if_running "$OTHER_PID_FILE" || true

set +e
rofi \
  -show frequent \
  -modi "frequent:$0 --mode frequent,apps:$0 --mode all" \
  -no-sort \
  -show-icons \
  -icon-theme 'Papirus-Dark' \
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
  -mesg 'Tab A: frequent top 5 | Tab B: all apps | Ctrl+Tab switches tabs' \
  -theme "$ROFI_THEME" \
  -pid "$PID_FILE"
rofi_status=$?
set -e

rm -f "$PID_FILE"
[ "$rofi_status" -eq 0 ] || exit 0
