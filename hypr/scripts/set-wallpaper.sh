#!/usr/bin/env sh
set -eu

wall_dirs="${WALLPAPER_DIRS:-$HOME/Pictures/wallpaper:$HOME/Pictures/Wallpapers}"
fallback_wall="$HOME/.cache/wallpapers/fallback-4k.png"
mkdir -p "$HOME/Pictures/wallpaper" "$HOME/Pictures/Wallpapers"

ensure_fallback_wall() {
  mkdir -p "$HOME/.cache/wallpapers"
  if [ ! -f "$fallback_wall" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "color=c=#0f172a:s=3840x2160" \
        -frames:v 1 "$fallback_wall" >/dev/null 2>&1 || true
    fi
  fi

  # Last-resort fallback in case ffmpeg is unavailable.
  if [ ! -f "$fallback_wall" ] && [ -f /usr/share/pixmaps/archlinux-logo.png ]; then
    cp /usr/share/pixmaps/archlinux-logo.png "$fallback_wall"
  fi
}

pick_wall() {
  old_ifs="$IFS"
  IFS=':'
  for dir in $wall_dirs; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \)
  done | sort -u
  IFS="$old_ifs"
}

pick_random_wall() {
  walls="$(pick_wall || true)"
  [ -n "$walls" ] || return 1

  current=""
  if [ -f "$HOME/.cache/current-wallpaper" ]; then
    current="$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null || true)"
  fi

  candidates="$walls"
  if [ -n "$current" ]; then
    candidates="$(printf '%s\n' "$walls" | grep -Fxv "$current" || true)"
    if [ -z "$candidates" ]; then
      candidates="$walls"
    fi
  fi

  if command -v shuf >/dev/null 2>&1; then
    printf '%s\n' "$candidates" | shuf -n1
  else
    printf '%s\n' "$candidates" | awk 'BEGIN{srand()} {a[NR]=$0} END{if (NR > 0) print a[int(rand()*NR)+1]}'
  fi
}

ensure_daemon() {
  if swww query >/dev/null 2>&1; then
    return 0
  fi

  pkill -x swww-daemon >/dev/null 2>&1 || true
  swww-daemon >/dev/null 2>&1 &

  i=0
  while [ "$i" -lt 10 ]; do
    sleep 0.2
    if swww query >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
  done

  return 1
}

ensure_theme_sync() {
  wall="$1"
  "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" "$wall" || true
  "$HOME/.config/hypr/scripts/theme-sync.sh" "$wall" || true
}

write_wall_cache() {
  wall="$1"
  printf '%s' "$wall" > "$HOME/.cache/current-wallpaper"
  ensure_theme_sync "$wall"
}

apply_wallpaper() {
  wall="$1"
  transition="$2"
  transition_type="${WALLPAPER_TRANSITION_TYPE:-fade}"
  transition_fps="${WALLPAPER_TRANSITION_FPS:-120}"
  transition_duration="${WALLPAPER_TRANSITION_DURATION:-1.3}"
  transition_step="${WALLPAPER_TRANSITION_STEP:-90}"
  resize_mode="${WALLPAPER_RESIZE_MODE:-crop}"

  prepared_wall="$(prepare_wall "$wall")"

  if [ "$transition" = "init" ]; then
    swww clear 000000 >/dev/null 2>&1 || true
    swww img "$prepared_wall" --resize "$resize_mode" --transition-type fade --transition-fps "$transition_fps" --transition-duration 1
    return 0
  fi

  swww clear 000000 >/dev/null 2>&1 || true
  swww img "$prepared_wall" \
    --resize "$resize_mode" \
    --transition-type "$transition_type" \
    --transition-step "$transition_step" \
    --transition-fps "$transition_fps" \
    --transition-duration "$transition_duration"
}

prepare_wall() {
  src="$1"
  ext="$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    png|webp)
      out_dir="$HOME/.cache/wallpapers/prepared"
      mkdir -p "$out_dir"
      key="$(printf '%s' "$src" | cksum | awk '{print $1}')"
      out_file="$out_dir/${key}.jpg"

      if [ ! -f "$out_file" ] || [ "$src" -nt "$out_file" ]; then
        python3 - "$src" "$out_file" <<'PY'
from PIL import Image
import sys

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src)
if "A" in im.getbands():
    bg = Image.new("RGB", im.size, (11, 15, 24))
    bg.paste(im, mask=im.getchannel("A"))
    bg.save(dst, "JPEG", quality=95)
else:
    im.convert("RGB").save(dst, "JPEG", quality=95)
PY
      fi
      printf '%s\n' "$out_file"
      return 0
      ;;
  esac

  printf '%s\n' "$src"
}

wayland_ready() {
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$runtime_dir/$WAYLAND_DISPLAY" ]
}

if [ "${1:-}" = "--init" ]; then
  if ! wayland_ready; then
    exit 0
  fi
  if ! ensure_daemon; then
    exit 0
  fi
  wall=""

  if [ -f "$HOME/.cache/current-wallpaper" ]; then
    wall="$(cat "$HOME/.cache/current-wallpaper")"
    # Prevent tiny distro icon from becoming the long-term default.
    if [ "$wall" = "/usr/share/pixmaps/archlinux-logo.png" ]; then
      wall=""
    fi
  fi

  if [ -z "$wall" ] && [ -n "$(pick_wall || true)" ]; then
    wall="$(pick_random_wall || true)"
  fi

  if [ -z "$wall" ]; then
    ensure_fallback_wall
    wall="$fallback_wall"
  fi

  apply_wallpaper "$wall" init || exit 0
  write_wall_cache "$wall"
  exit 0
fi

if [ "${1:-}" = "--pick" ]; then
  chosen="$(pick_wall | sed "s|$HOME/||" | rofi -dmenu -i -p "Wallpaper")"
  [ -n "$chosen" ] || exit 0
  wall="$HOME/$chosen"
elif [ "${1:-}" = "--next" ]; then
  wall="$(pick_random_wall || true)"
  if [ -z "$wall" ]; then
    ensure_fallback_wall
    wall="$fallback_wall"
  fi
else
  if [ -n "${1:-}" ]; then
    wall="$1"
  else
    if [ -n "$(pick_wall || true)" ]; then
      wall="$(pick_wall | head -n1)"
    else
      ensure_fallback_wall
      wall="$fallback_wall"
    fi
  fi
fi

if ! wayland_ready; then
  exit 0
fi

if ! ensure_daemon; then
  exit 0
fi

apply_wallpaper "$wall" normal || exit 0
write_wall_cache "$wall"
