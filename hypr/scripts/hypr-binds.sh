#!/usr/bin/env bash
set -euo pipefail

conf_file="${HYPR_CONF_PATH:-$HOME/.config/hypr/hyprland.conf}"
mode="menu"

usage() {
  cat <<'EOF'
Usage: hypr-binds.sh [--print] [--conf <path>]
  --print        Print parsed keybind table to stdout
  --conf <path>  Parse a specific hyprland.conf file
EOF
}

while (($#)); do
  case "$1" in
    --print)
      mode="print"
      ;;
    --conf)
      shift
      conf_file="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ ! -f "$conf_file" ]; then
  echo "hypr-binds: missing config: $conf_file" >&2
  exit 1
fi

parse_rows() {
  awk '
    function trim(v) {
      gsub(/^[[:space:]]+/, "", v)
      gsub(/[[:space:]]+$/, "", v)
      return v
    }

    function normalize_mods(v) {
      v = trim(v)
      gsub(/\$mainMod/, "SUPER", v)
      gsub(/[[:space:]]+/, "+", v)
      gsub(/\+\+/, "+", v)
      return v
    }

    /^[[:space:]]*bind[a-z]*[[:space:]]*=/ {
      line = $0
      match(line, /^[[:space:]]*bind[a-z]*/)
      bind_type = substr(line, RSTART, RLENGTH)

      sub(/^[[:space:]]*bind[a-z]*[[:space:]]*=[[:space:]]*/, "", line)

      n = split(line, parts, ",")
      if (n < 3) {
        next
      }

      mods = normalize_mods(parts[1])
      key = trim(parts[2])
      dispatcher = trim(parts[3])

      args = ""
      for (i = 4; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        if (args != "") {
          args = args ", "
        }
        args = args part
      }

      combo = key
      if (mods != "") {
        combo = mods "+" key
      }

      command = dispatcher
      if (args != "") {
        command = command " " args
      }

      print bind_type "\t" combo "\t" command
    }
  ' "$conf_file"
}

format_rows() {
  awk -F '\t' '
    function map_type(v) {
      if (v == "bindm") return "mouse"
      if (v == "bindl") return "lock"
      if (v == "bindel") return "lock-r"
      if (v == "bind") return "key"
      return v
    }
    {
      type = map_type($1)
      key = $2
      cmd = $3
      if (length(key) > 38) {
        key = substr(key, 1, 35) "..."
      }
      printf "%-7s | %-38s | %s\n", type, key, cmd
    }
  '
}

table_output="$(parse_rows | format_rows)"
if [ -z "$table_output" ]; then
  echo "hypr-binds: no bind lines found in $conf_file" >&2
  exit 1
fi

if [ "$mode" = "print" ]; then
  printf '%s\n' "$table_output"
  exit 0
fi

pick=""
if command -v rofi >/dev/null 2>&1; then
  set +e
  pick="$(
    printf '%s\n' "$table_output" | rofi -dmenu -i \
      -p 'Hypr Keys' \
      -mesg 'Enter copies row | Esc closes' \
      -theme "$HOME/.config/rofi/actions.rasi"
  )"
  status=$?
  set -e
  [ "$status" -eq 0 ] || exit 0
elif command -v fzf >/dev/null 2>&1; then
  set +e
  pick="$(
    printf '%s\n' "$table_output" | fzf \
      --height=70% \
      --layout=reverse \
      --border \
      --prompt='hypr-binds> ' \
      --header='Enter copies row | Esc closes'
  )"
  status=$?
  set -e
  [ "$status" -eq 0 ] || exit 0
else
  printf '%s\n' "$table_output"
  exit 0
fi

[ -n "$pick" ] || exit 0

if command -v wl-copy >/dev/null 2>&1; then
  printf '%s\n' "$pick" | wl-copy
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a Hyprland "Keybind copied" "$pick"
  fi
fi
