#!/usr/bin/env sh
set -eu

wall="${1:-}"
cache_dir="$HOME/.cache/hypr"
mkdir -p "$cache_dir"
hooks_dir="$HOME/.config/hypr/scripts/theme-hooks.d"

palette_json="$cache_dir/theme-palette.json"
waybar_colors="$cache_dir/theme-colors-waybar.css"
swaync_colors="$cache_dir/theme-colors-swaync.css"
rofi_colors="$cache_dir/theme-colors-rofi.rasi"
eww_colors="$cache_dir/theme-colors-eww.scss"
kitty_colors="$cache_dir/theme-colors-kitty.conf"
hyprlock_colors="$cache_dir/theme-colors-hyprlock.conf"
gtk3_css="$HOME/.config/gtk-3.0/gtk.css"
gtk4_css="$HOME/.config/gtk-4.0/gtk.css"

if [ -z "$wall" ] || [ ! -f "$wall" ]; then
  if [ -f "$HOME/.cache/current-wallpaper" ]; then
    wall="$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null || true)"
  fi
fi

if [ -z "$wall" ] || [ ! -f "$wall" ]; then
  exit 0
fi

python3 - "$wall" "$palette_json" <<'PY'
import colorsys
import json
import sys
from pathlib import Path

from PIL import Image

wall = Path(sys.argv[1])
out = Path(sys.argv[2])

img = Image.open(wall).convert("RGB")
img.thumbnail((500, 500))
quant = img.quantize(colors=10, method=Image.Quantize.FASTOCTREE)
pal = quant.getpalette()
colors = []
for count, idx in sorted(quant.getcolors() or [], reverse=True):
    rgb = tuple(pal[idx * 3: idx * 3 + 3])
    if len(rgb) != 3:
        continue
    colors.append((count, rgb))

if not colors:
    colors = [(1, (122, 162, 247)), (1, (79, 214, 190)), (1, (15, 18, 28))]

def lum(rgb):
    r, g, b = [c / 255 for c in rgb]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def sat(rgb):
    r, g, b = [c / 255 for c in rgb]
    return colorsys.rgb_to_hsv(r, g, b)[1]

def blend(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))

def to_hex(rgb):
    return "#%02x%02x%02x" % rgb

sorted_by_lum = sorted([rgb for _, rgb in colors], key=lum)
bg_raw = sorted_by_lum[0]
bg = blend(bg_raw, (10, 14, 24), 0.50)
surface = blend(bg, (255, 255, 255), 0.12)

candidates = sorted([rgb for _, rgb in colors], key=lambda c: (sat(c), -lum(c)), reverse=True)
accent = None
for rgb in candidates:
    l = lum(rgb)
    if 0.20 <= l <= 0.86 and sat(rgb) >= 0.18:
        accent = rgb
        break
if accent is None:
    accent = (122, 162, 247)

accent2 = None
for rgb in candidates:
    if rgb == accent:
        continue
    dist = sum(abs(rgb[i] - accent[i]) for i in range(3))
    if dist >= 90:
        accent2 = rgb
        break
if accent2 is None:
    accent2 = (79, 214, 190)

text = (232, 238, 252) if lum(bg) < 0.42 else (18, 24, 37)
muted = blend(text, bg, 0.38)
warn = (255, 150, 108)
danger = (255, 117, 127)

out_data = {
    "bg": to_hex(bg),
    "bg_soft": to_hex(blend(bg, surface, 0.35)),
    "surface": to_hex(surface),
    "text": to_hex(text),
    "muted": to_hex(muted),
    "accent": to_hex(accent),
    "accent2": to_hex(accent2),
    "warn": to_hex(warn),
    "danger": to_hex(danger),
}
out.write_text(json.dumps(out_data, indent=2), encoding="utf-8")
PY

read_color() {
  key="$1"
  jq -r --arg k "$key" '.[$k]' "$palette_json"
}

hex_to_rgb_csv() {
  hex="${1#\#}"
  rr="${hex%????}"
  tail="${hex#??}"
  gg="${tail%??}"
  bb="${hex#????}"
  r=$((16#${rr}))
  g=$((16#${gg}))
  b=$((16#${bb}))
  printf '%s, %s, %s' "$r" "$g" "$b"
}

bg="$(read_color bg)"
bg_soft="$(read_color bg_soft)"
surface="$(read_color surface)"
text="$(read_color text)"
muted="$(read_color muted)"
accent="$(read_color accent)"
accent2="$(read_color accent2)"
warn="$(read_color warn)"
danger="$(read_color danger)"

cat > "$waybar_colors" <<EOF2
@define-color bg ${bg};
@define-color bg_soft ${bg_soft};
@define-color surface ${surface};
@define-color text ${text};
@define-color muted ${muted};
@define-color accent ${accent};
@define-color accent2 ${accent2};
@define-color warn ${warn};
@define-color danger ${danger};
EOF2

cat > "$swaync_colors" <<EOF2
@define-color bg ${bg};
@define-color bg_soft ${bg_soft};
@define-color surface ${surface};
@define-color text ${text};
@define-color muted ${muted};
@define-color accent ${accent};
@define-color accent2 ${accent2};
@define-color warn ${warn};
@define-color danger ${danger};
EOF2

cat > "$rofi_colors" <<EOF2
* {
    bg: ${bg}ef;
    bg-alt: ${bg_soft}ee;
    fg: ${text};
    fg-muted: ${muted};
    accent: ${accent};
    good: ${accent2};
    bad: ${danger};
}
EOF2

cat > "$eww_colors" <<EOF2
\$bg: rgba($(hex_to_rgb_csv "$bg"), 0.94);
\$surface: rgba($(hex_to_rgb_csv "$surface"), 0.96);
\$border: rgba($(hex_to_rgb_csv "$accent"), 0.34);
\$text: ${text};
\$muted: ${muted};
\$accent: ${accent};
\$accent2: ${accent2};
EOF2

cat > "$kitty_colors" <<EOF2
foreground ${text}
background ${bg}
selection_foreground ${bg}
selection_background ${accent}
cursor ${accent}
cursor_text_color ${bg}
color0  ${bg}
color1  ${danger}
color2  ${accent2}
color3  ${warn}
color4  ${accent}
color5  ${accent2}
color6  ${accent}
color7  ${text}
color8  ${bg_soft}
color9  ${danger}
color10 ${accent2}
color11 ${warn}
color12 ${accent}
color13 ${accent2}
color14 ${accent}
color15 ${text}
EOF2

cat > "$hyprlock_colors" <<EOF2
\$lock_bg = rgb(${bg#\#})
\$lock_fg = rgb(${text#\#})
\$lock_accent = rgb(${accent#\#})
EOF2

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cat > "$gtk3_css" <<EOF2
@define-color theme_bg_color ${bg};
@define-color theme_fg_color ${text};
@define-color theme_selected_bg_color ${accent};
@define-color theme_selected_fg_color ${bg};
EOF2
cp "$gtk3_css" "$gtk4_css"

printf '%s\n' "$accent" > "$cache_dir/current-accent"

# Optional external themers (run only if installed).
if command -v wal >/dev/null 2>&1; then
  timeout 15 wal -q -n -i "$wall" >/dev/null 2>&1 || true
fi

if command -v matugen >/dev/null 2>&1; then
  timeout 20 matugen image "$wall" >/dev/null 2>&1 || true
fi

if command -v pywalfox >/dev/null 2>&1; then
  timeout 15 pywalfox update >/dev/null 2>&1 || true
fi

if pgrep -x waybar >/dev/null 2>&1; then
  pkill -USR2 -x waybar >/dev/null 2>&1 || true
fi

if command -v swaync-client >/dev/null 2>&1; then
  timeout 3 swaync-client -rs >/dev/null 2>&1 || true
fi

if command -v eww >/dev/null 2>&1 && [ -d "$HOME/.config/eww" ]; then
  eww --config "$HOME/.config/eww" reload >/dev/null 2>&1 || true
fi

if command -v kitty >/dev/null 2>&1; then
  kitty @ set-colors -a "$kitty_colors" >/dev/null 2>&1 || true
fi

# VSCode dynamic palette sync (if installed/config exists).
if [ -f "$HOME/.config/Code/User/settings.json" ]; then
  tmp_file="$(mktemp)"
  jq --arg bg "$bg" --arg text "$text" --arg accent "$accent" --arg muted "$muted" '
    . + {
      "workbench.colorCustomizations": (
        (.["workbench.colorCustomizations"] // {}) + {
          "editor.background": $bg,
          "editor.foreground": $text,
          "activityBar.background": $bg,
          "activityBar.foreground": $text,
          "statusBar.background": $accent,
          "statusBar.foreground": $bg,
          "sideBar.background": $bg,
          "sideBar.foreground": $text,
          "titleBar.activeBackground": $bg,
          "titleBar.activeForeground": $text,
          "tab.activeBackground": $bg,
          "tab.activeForeground": $text,
          "tab.inactiveForeground": $muted
        }
      )
    }
  ' "$HOME/.config/Code/User/settings.json" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$HOME/.config/Code/User/settings.json" || rm -f "$tmp_file"
fi

# Optional per-app hooks for extra utilities (btop, custom tools, etc.).
if [ -d "$hooks_dir" ]; then
  for hook in "$hooks_dir"/*.sh; do
    [ -f "$hook" ] || continue
    THEME_WALL="$wall" \
    THEME_CACHE_DIR="$cache_dir" \
    THEME_PALETTE_JSON="$palette_json" \
    THEME_BG="$bg" \
    THEME_BG_SOFT="$bg_soft" \
    THEME_SURFACE="$surface" \
    THEME_TEXT="$text" \
    THEME_MUTED="$muted" \
    THEME_ACCENT="$accent" \
    THEME_ACCENT2="$accent2" \
    THEME_WARN="$warn" \
    THEME_DANGER="$danger" \
    sh "$hook" >/dev/null 2>&1 || true
  done
fi
