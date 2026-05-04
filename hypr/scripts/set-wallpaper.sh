#!/usr/bin/env sh
set -eu

wall_dirs="${WALLPAPER_DIRS:-$HOME/Pictures/wallpaper/1080p:$HOME/Pictures/wallpaper/4k:$HOME/Pictures/wallpaper:$HOME/Pictures/Wallpapers}"
fallback_wall="$HOME/.cache/wallpapers/fallback-4k.png"
mkdir -p \
  "$HOME/Pictures/wallpaper/1080p" \
  "$HOME/Pictures/wallpaper/4k" \
  "$HOME/Pictures/wallpaper" \
  "$HOME/Pictures/Wallpapers" \
  "$HOME/Pictures/wallpaper-sources"

emit_event() {
  if [ -x "$HOME/.config/hypr/scripts/lib/log.sh" ]; then
    "$HOME/.config/hypr/scripts/lib/log.sh" --emit "$1" wallpaper "$2" "${3:-}" "${4:-}" "${5:-}" >/dev/null 2>&1 || true
  fi
}

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
    find "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \)
  done | sort -u
  IFS="$old_ifs"
}

preferred_output_size() {
  hyprctl monitors -j 2>/dev/null | jq -r '((map(select(.focused == true))[0] // .[0]) | "\(.width // 1920) \(.height // 1080)")' 2>/dev/null || echo "1920 1080"
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

apply_with_hyprpaper() {
  wall_path="$1"
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v hyprpaper >/dev/null 2>&1 || return 1

  if ! pgrep -x hyprpaper >/dev/null 2>&1; then
    pkill -x hyprpaper >/dev/null 2>&1 || true
    hyprpaper >/dev/null 2>&1 &

    i=0
    while [ "$i" -lt 10 ]; do
      sleep 0.2
      if pgrep -x hyprpaper >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
    done

    pgrep -x hyprpaper >/dev/null 2>&1 || return 1
  fi

  # Preload is optional; some setups still accept wallpaper even if preload
  # fails for a given file/state.
  hyprctl hyprpaper preload "$wall_path" >/dev/null 2>&1 || true

  monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
  success=1
  if [ -n "$monitors" ]; then
    old_ifs="$IFS"
    IFS='
'
    for mon in $monitors; do
      [ -n "$mon" ] || continue
      if hyprctl hyprpaper wallpaper "$mon,$wall_path" >/dev/null 2>&1; then
        success=0
      fi
    done
    IFS="$old_ifs"
    if [ "$success" -eq 0 ]; then
      return 0
    fi
  fi

  hyprctl hyprpaper wallpaper ",$wall_path" >/dev/null 2>&1 || return 1
  return 0
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
  emit_event info "Wallpaper applied" "$wall"
}

apply_wallpaper() {
  wall="$1"
  transition="$2"

  prepared_wall="$(prepare_wall "$wall")"

  if apply_with_hyprpaper "$prepared_wall" || apply_with_hyprpaper "$wall"; then
    return 0
  fi

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a Wallpaper "Wallpaper backend unavailable" "Install/start hyprpaper."
  fi
  emit_event error "Wallpaper backend unavailable" "Install/start hyprpaper."
  return 1
}

prepare_wall() {
  src="$1"
  read -r mon_w mon_h <<EOF_SIZE
$(preferred_output_size)
EOF_SIZE
  case "$mon_w $mon_h" in
    ''|'null null') mon_w=1920; mon_h=1080 ;;
  esac

  canvas_mode="${WALLPAPER_CANVAS_MODE:-blurpad}"
  out_dir="$HOME/.cache/wallpapers/prepared"
  mkdir -p "$out_dir"
  key="$(printf '%s|%s|%s|%s' "$src" "$mon_w" "$mon_h" "$canvas_mode" | cksum | awk '{print $1}')"
  out_file="$out_dir/${key}.jpg"

  if [ ! -f "$out_file" ] || [ "$src" -nt "$out_file" ]; then
    python3 - "$src" "$out_file" "$mon_w" "$mon_h" "$canvas_mode" <<'PY'
from PIL import Image, ImageFilter, ImageOps
import sys

src, dst = sys.argv[1], sys.argv[2]
target_w, target_h = int(sys.argv[3]), int(sys.argv[4])
canvas_mode = sys.argv[5]

with Image.open(src) as raw:
    im = ImageOps.exif_transpose(raw)
    if "A" in im.getbands():
        flattened = Image.new("RGB", im.size, (11, 15, 24))
        flattened.paste(im.convert("RGBA"), mask=im.getchannel("A"))
        im = flattened
    else:
        im = im.convert("RGB")

    if canvas_mode == "raw":
        im.save(dst, "JPEG", quality=95)
        raise SystemExit

    bg = ImageOps.fit(im.copy(), (target_w, target_h), method=Image.Resampling.LANCZOS)
    if canvas_mode == "blurpad":
        bg = bg.filter(ImageFilter.GaussianBlur(radius=22))
    else:
        bg = Image.new("RGB", (target_w, target_h), (11, 15, 24))

    fg = im.copy()
    fg.thumbnail((target_w, target_h), Image.Resampling.LANCZOS)
    x = (target_w - fg.width) // 2
    y = (target_h - fg.height) // 2
    bg.paste(fg, (x, y))
    bg.save(dst, "JPEG", quality=95)
PY
  fi

  printf '%s\n' "$out_file"
}

wayland_ready() {
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$runtime_dir/$WAYLAND_DISPLAY" ]
}

if [ "${1:-}" = "--init" ]; then
  if ! wayland_ready; then
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

apply_wallpaper "$wall" normal || exit 0
write_wall_cache "$wall"
