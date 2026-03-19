#!/usr/bin/env sh
set -eu

mode="${1:-full}"
css_file="$HOME/.config/wlogout/style.css"
palette_file="$HOME/.cache/hypr/theme-palette.json"

if [ "$mode" = "futuristic" ]; then
  mode="full"
  css_file="$HOME/.config/wlogout/style-futuristic.css"
fi

if [ "$mode" = "minimal" ]; then
  mode="full"
  css_file="$HOME/.config/wlogout/style.css"
fi

theme_hex() {
  key="$1"
  default="$2"
  if command -v jq >/dev/null 2>&1 && [ -f "$palette_file" ]; then
    v="$(jq -r --arg k "$key" '.[$k] // empty' "$palette_file" 2>/dev/null || true)"
    if [ -n "$v" ] && [ "$v" != "null" ]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi
  printf '%s\n' "$default"
}

hex_to_rgb() {
  h="${1#\#}"
  if [ "${#h}" -ne 6 ]; then
    printf '255,255,255'
    return 0
  fi
  hr="$(printf '%s' "$h" | cut -c1-2)"
  hg="$(printf '%s' "$h" | cut -c3-4)"
  hb="$(printf '%s' "$h" | cut -c5-6)"
  r="$(printf '%d' "0x$hr")"
  g="$(printf '%d' "0x$hg")"
  b="$(printf '%d' "0x$hb")"
  printf '%s,%s,%s' "$r" "$g" "$b"
}

prepare_runtime_css() {
  src="$1"
  dst="$2"
  cp "$src" "$dst"

  bg="$(theme_hex bg "#1a1b1f")"
  bg_soft="$(theme_hex bg_soft "#242529")"
  surface="$(theme_hex surface "#38393c")"
  text="$(theme_hex text "#e8eefc")"
  accent="$(theme_hex accent "#ae775b")"
  danger="$(theme_hex danger "#ff757f")"

  bg_rgb="$(hex_to_rgb "$bg")"
  bg_soft_rgb="$(hex_to_rgb "$bg_soft")"
  surface_rgb="$(hex_to_rgb "$surface")"
  danger_rgb="$(hex_to_rgb "$danger")"

  sed -i \
    -e "s/#e8eefc/$text/g" \
    -e "s/#ae775b/$accent/g" \
    -e "s/#ff757f/$danger/g" \
    -e "s/rgba(26, 27, 31, 0.82)/rgba(${bg_rgb}, 0.82)/g" \
    -e "s/rgba(26, 27, 31, 0.86)/rgba(${bg_rgb}, 0.86)/g" \
    -e "s/rgba(36, 37, 41, 0.9)/rgba(${bg_soft_rgb}, 0.9)/g" \
    -e "s/rgba(56, 57, 60, 0.75)/rgba(${surface_rgb}, 0.75)/g" \
    -e "s/rgba(56, 57, 60, 0.82)/rgba(${surface_rgb}, 0.82)/g" \
    -e "s/rgba(255, 117, 127, 0.28)/rgba(${danger_rgb}, 0.28)/g" \
    -e "s/rgba(255, 117, 127, 0.3)/rgba(${danger_rgb}, 0.3)/g" \
    -e "s/rgba(255, 117, 127, 0.4)/rgba(${danger_rgb}, 0.4)/g" \
    -e "s/rgba(255, 117, 127, 0.42)/rgba(${danger_rgb}, 0.42)/g" \
    "$dst"
}

show_compact_menu() {
  choice="$(
    printf '%s\n' \
      "󰌾  Lock" \
      "󰤄  Sleep" \
      "󰒲  Hibernate" \
      "󰍃  Logout" \
      "󰜉  Reboot" \
      "󰐥  Shutdown" \
      "󰑐  Restart Waybar" \
    | rofi -dmenu -i -p "Power" -theme "$HOME/.config/rofi/actions.rasi"
  )"

  case "$choice" in
    "󰌾  Lock") ~/.config/hypr/scripts/lock.sh ;;
    "󰤄  Sleep") systemctl suspend ;;
    "󰒲  Hibernate") systemctl hibernate ;;
    "󰍃  Logout") hyprctl dispatch exit ;;
    "󰜉  Reboot") systemctl reboot ;;
    "󰐥  Shutdown") systemctl poweroff ;;
    "󰑐  Restart Waybar") ~/.config/hypr/scripts/restart-waybar.sh ;;
    *) exit 0 ;;
  esac
}

if [ "$mode" = "compact" ]; then
  show_compact_menu
  exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
  runtime_css="$HOME/.config/wlogout/.runtime-$(basename "$css_file" .css).css"

  # Toggle behavior: if already open, close it instead of spawning another one.
  if pgrep -x wlogout >/dev/null 2>&1; then
    pkill -x wlogout
    exit 0
  fi

  prepare_runtime_css "$css_file" "$runtime_css"

  exec wlogout \
    --layout "$HOME/.config/wlogout/layout" \
    --css "$runtime_css" \
    --buttons-per-row 3 \
    --column-spacing 8 \
    --row-spacing 8
fi

show_compact_menu
