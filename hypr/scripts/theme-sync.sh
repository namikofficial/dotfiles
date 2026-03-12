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
qt5_colors_dir="$HOME/.config/qt5ct/colors"
qt6_colors_dir="$HOME/.config/qt6ct/colors"
qt5_scheme="$qt5_colors_dir/NoxflowDynamic.conf"
qt6_scheme="$qt6_colors_dir/NoxflowDynamic.conf"
qt5_conf="$HOME/.config/qt5ct/qt5ct.conf"
qt6_conf="$HOME/.config/qt6ct/qt6ct.conf"
kdeglobals="$HOME/.config/kdeglobals"
kvantum_dir="$HOME/.config/Kvantum"
kvantum_theme_dir="$kvantum_dir/NoxflowDynamic"
kvantum_theme_conf="$kvantum_theme_dir/NoxflowDynamic.kvconfig"
kvantum_theme_svg="$kvantum_theme_dir/NoxflowDynamic.svg"
kvantum_main_conf="$kvantum_dir/kvantum.kvconfig"
waybar_before_hash=""
waybar_after_hash=""
kitty_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

kitty_remote_all() {
  command -v kitty >/dev/null 2>&1 || return 0
  for sock in "$kitty_runtime_dir"/kitty-control*; do
    [ -S "$sock" ] || continue
    kitty @ --to "unix:$sock" "$@" >/dev/null 2>&1 || true
  done
}

if [ -f "$waybar_colors" ]; then
  waybar_before_hash="$(sha256sum "$waybar_colors" | awk '{print $1}')"
fi

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

from PIL import Image, ImageEnhance

wall = Path(sys.argv[1])
out = Path(sys.argv[2])

img = Image.open(wall).convert("RGB")
img.thumbnail((640, 640))
img = ImageEnhance.Color(img).enhance(1.18)
img = ImageEnhance.Contrast(img).enhance(1.08)
quant = img.quantize(colors=48, method=Image.Quantize.MEDIANCUT)
pal = quant.getpalette()
entries = []
color_rows = quant.getcolors() or []
total = sum(count for count, _ in color_rows) or 1

for count, idx in sorted(color_rows, reverse=True):
    rgb = tuple(pal[idx * 3 : idx * 3 + 3])
    if len(rgb) != 3:
        continue
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    entries.append(
        {
            "count": count,
            "fraction": count / total,
            "rgb": rgb,
            "h": h,
            "s": s,
            "v": v,
            "lum": lum,
            "chroma": (max(rgb) - min(rgb)) / 255,
        }
    )

if not entries:
    entries = [
        {"count": 1, "fraction": 1.0, "rgb": (122, 162, 247), "h": 0.61, "s": 0.50, "v": 0.97, "lum": 0.60, "chroma": 0.49},
        {"count": 1, "fraction": 1.0, "rgb": (79, 214, 190), "h": 0.47, "s": 0.63, "v": 0.84, "lum": 0.70, "chroma": 0.53},
        {"count": 1, "fraction": 1.0, "rgb": (15, 18, 28), "h": 0.63, "s": 0.46, "v": 0.11, "lum": 0.07, "chroma": 0.05},
    ]

def lum(rgb):
    r, g, b = [c / 255 for c in rgb]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def blend(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))

def to_hex(rgb):
    return "#%02x%02x%02x" % rgb

def contrast_ratio(a, b):
    la = lum(a)
    lb = lum(b)
    l1, l2 = (la, lb) if la >= lb else (lb, la)
    return (l1 + 0.05) / (l2 + 0.05)

def hue_distance(a, b):
    diff = abs(a - b)
    return min(diff, 1 - diff)

def polish_accent(rgb, sat_target, val_target):
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    s = max(s, sat_target * 0.70)
    s = min(0.76, s + max(0.0, sat_target - s) * 0.86)
    v = max(v, val_target * 0.72)
    v = min(0.90, v + max(0.0, val_target - v) * 0.62)
    return tuple(int(round(channel * 255)) for channel in colorsys.hsv_to_rgb(h, s, v))

dark_candidates = [entry for entry in entries if entry["lum"] <= 0.28]
if not dark_candidates:
    dark_candidates = entries[:]

def bg_score(entry):
    return (
        entry["fraction"] * 2.1
        - abs(entry["lum"] - 0.12) * 1.45
        - entry["s"] * 0.70
        - entry["chroma"] * 0.35
    )

bg_seed = max(dark_candidates, key=bg_score)["rgb"]
bg = blend(bg_seed, (10, 14, 24), 0.45)
if lum(bg) > 0.20:
    bg = blend(bg, (8, 11, 18), 0.28)
surface = blend(bg, (255, 255, 255), 0.13)
bg_soft = blend(bg, surface, 0.34)

accent_candidates = []
for entry in entries:
    rgb = entry["rgb"]
    c_bg = contrast_ratio(rgb, bg)
    score = (
        entry["s"] * 2.45
        + entry["chroma"] * 1.25
        + min(c_bg, 3.0) * 0.46
        + min(entry["fraction"] * 5.0, 0.28)
        - abs(entry["lum"] - 0.56) * 0.95
    )
    if entry["fraction"] > 0.16 and entry["s"] < 0.28:
        score -= 0.45
    if entry["lum"] < 0.16 or entry["lum"] > 0.86 or c_bg < 1.35:
        continue
    if entry["s"] < 0.14 and entry["chroma"] < 0.10:
        continue
    accent_candidates.append((score, entry))

if accent_candidates:
    accent_candidates.sort(reverse=True, key=lambda item: item[0])
    accent_seed = accent_candidates[0][1]
else:
    accent_seed = {"rgb": (111, 148, 201), "h": 0.60, "s": 0.45, "v": 0.79, "lum": 0.54, "chroma": 0.35}

accent = polish_accent(accent_seed["rgb"], 0.52, 0.82)

secondary_pool = []
for score, entry in accent_candidates[1:]:
    dh = hue_distance(entry["h"], accent_seed["h"])
    if dh < 0.10:
        continue
    secondary_score = score + dh * 2.20 - abs(entry["lum"] - 0.54) * 0.25
    secondary_pool.append((secondary_score, entry))

if secondary_pool:
    secondary_pool.sort(reverse=True, key=lambda item: item[0])
    accent2_seed = secondary_pool[0][1]
    accent2 = polish_accent(accent2_seed["rgb"], 0.38, 0.76)
else:
    rotate = 0.17 if accent_seed["h"] < 0.5 else -0.17
    h = (accent_seed["h"] + rotate) % 1.0
    accent2 = tuple(
        int(round(channel * 255))
        for channel in colorsys.hsv_to_rgb(h, 0.34, max(0.62, accent_seed["v"]))
    )

accent = blend(accent, surface, 0.10)
accent2 = blend(accent2, surface, 0.08)

while contrast_ratio(accent, bg) < 2.35:
    accent = blend(accent, (255, 255, 255), 0.12)
while contrast_ratio(accent2, bg) < 2.05:
    accent2 = blend(accent2, (255, 255, 255), 0.10)

if hue_distance(
    colorsys.rgb_to_hsv(*(c / 255 for c in accent))[0],
    colorsys.rgb_to_hsv(*(c / 255 for c in accent2))[0],
) < 0.10:
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in accent2))
    h = (h + 0.16) % 1.0
    accent2 = tuple(int(round(channel * 255)) for channel in colorsys.hsv_to_rgb(h, max(s, 0.30), max(v, 0.70)))

text = (232, 238, 252) if lum(bg) < 0.42 else (18, 24, 37)
muted = blend(text, bg, 0.38)
warn = (255, 166, 110)
danger = (255, 117, 127)

out_data = {
    "bg": to_hex(bg),
    "bg_soft": to_hex(bg_soft),
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
bg_rgb="$(hex_to_rgb_csv "$bg")"
bg_soft_rgb="$(hex_to_rgb_csv "$bg_soft")"
surface_rgb="$(hex_to_rgb_csv "$surface")"
text_rgb="$(hex_to_rgb_csv "$text")"
muted_rgb="$(hex_to_rgb_csv "$muted")"
accent_rgb="$(hex_to_rgb_csv "$accent")"
accent2_rgb="$(hex_to_rgb_csv "$accent2")"

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

if [ -f "$waybar_colors" ]; then
  waybar_after_hash="$(sha256sum "$waybar_colors" | awk '{print $1}')"
fi

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
\$bg: rgba($(hex_to_rgb_csv "$bg"), 0.78);
\$surface: rgba($(hex_to_rgb_csv "$surface"), 0.84);
\$border: rgba($(hex_to_rgb_csv "$accent"), 0.18);
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
url_color ${accent2}
active_border_color ${accent}
inactive_border_color ${surface}
bell_border_color ${warn}
tab_bar_background ${bg}
active_tab_foreground ${bg}
active_tab_background ${accent}
inactive_tab_foreground ${muted}
inactive_tab_background ${bg_soft}
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

mkdir -p "$qt5_colors_dir" "$qt6_colors_dir"
cat > "$qt5_scheme" <<EOF2
[ColorScheme]
active_colors=$text_rgb
disabled_colors=$muted_rgb
inactive_colors=$muted_rgb

[Colors:Window]
BackgroundNormal=$bg_rgb
BackgroundAlternate=$bg_soft_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb

[Colors:View]
BackgroundNormal=$surface_rgb
BackgroundAlternate=$bg_soft_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb
DecorationFocus=$accent_rgb
DecorationHover=$accent2_rgb

[Colors:Button]
BackgroundNormal=$bg_soft_rgb
BackgroundAlternate=$surface_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb

[Colors:Selection]
BackgroundNormal=$accent_rgb
BackgroundAlternate=$accent2_rgb
ForegroundNormal=$bg_rgb
ForegroundInactive=$bg_rgb
ForegroundActive=$bg_rgb

[Colors:Tooltip]
BackgroundNormal=$surface_rgb
ForegroundNormal=$text_rgb
EOF2
cp "$qt5_scheme" "$qt6_scheme"

set_qtct_value() {
  conf="$1"
  key="$2"
  val="$3"
  [ -f "$conf" ] || return 0
  if grep -q "^$key=" "$conf"; then
    sed -i "s|^$key=.*|$key=$val|" "$conf" || true
  else
    # Place in [Appearance] if present, otherwise append.
    if grep -q '^\[Appearance\]' "$conf"; then
      awk -v k="$key" -v v="$val" '
        BEGIN {done=0}
        /^\[Appearance\]/ {print; print k "=" v; done=1; next}
        {print}
        END {if (!done) print k "=" v}
      ' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
    else
      printf '\n%s=%s\n' "$key" "$val" >> "$conf"
    fi
  fi
}

set_qtct_value "$qt5_conf" "color_scheme_path" "$qt5_scheme"
set_qtct_value "$qt6_conf" "color_scheme_path" "$qt6_scheme"
set_qtct_value "$qt5_conf" "icon_theme" "Papirus-Dark"
set_qtct_value "$qt6_conf" "icon_theme" "Papirus-Dark"

cat > "$kdeglobals" <<EOF2
[General]
ColorScheme=NoxflowDynamic
TerminalApplication=kitty

[Icons]
Theme=Papirus-Dark

[KDE]
widgetStyle=kvantum

[Colors:Window]
BackgroundNormal=$bg_rgb
BackgroundAlternate=$bg_soft_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb

[Colors:View]
BackgroundNormal=$surface_rgb
BackgroundAlternate=$bg_soft_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb
DecorationFocus=$accent_rgb
DecorationHover=$accent2_rgb

[Colors:Button]
BackgroundNormal=$bg_soft_rgb
BackgroundAlternate=$surface_rgb
ForegroundNormal=$text_rgb
ForegroundInactive=$muted_rgb
ForegroundActive=$accent_rgb

[Colors:Selection]
BackgroundNormal=$accent_rgb
ForegroundNormal=$bg_rgb
EOF2

mkdir -p "$kvantum_theme_dir"
if [ -f "/usr/share/Kvantum/KvArcDark/KvArcDark.svg" ]; then
  cp "/usr/share/Kvantum/KvArcDark/KvArcDark.svg" "$kvantum_theme_svg"
fi

cat > "$kvantum_theme_conf" <<EOF2
[%General]
author=noxflow
comment=Dynamic wallpaper-synced Kvantum theme
x11drag=menubar_and_primary_toolbar
composite=true
translucent_windows=true
blurring=true
popup_blurring=true
respect_DE=true

[GeneralColors]
window.color=$bg
base.color=$surface
alt.base.color=$bg_soft
button.color=$bg_soft
light.color=$accent2
mid.light.color=$surface
dark.color=#101216
mid.color=#1a1f2a
highlight.color=$accent
inactive.highlight.color=$accent2
text.color=$text
window.text.color=$text
button.text.color=$text
disabled.text.color=$muted
tooltip.text.color=$text
highlight.text.color=$bg
link.color=$accent2
link.visited.color=$accent
progress.indicator.text.color=$bg

[Hacks]
respect_darkness=true
transparent_menutitle=true
EOF2

cat > "$kvantum_main_conf" <<EOF2
[General]
theme=NoxflowDynamic
EOF2

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

if pgrep -x waybar >/dev/null 2>&1 && [ "$waybar_before_hash" != "$waybar_after_hash" ]; then
  pkill -USR2 -x waybar >/dev/null 2>&1 || true
fi

if command -v swaync-client >/dev/null 2>&1; then
  timeout 3 swaync-client -rs >/dev/null 2>&1 || true
fi

if command -v eww >/dev/null 2>&1 && [ -d "$HOME/.config/eww" ]; then
  eww --config "$HOME/.config/eww" reload >/dev/null 2>&1 || true
fi

kitty_remote_all set-colors -a "$kitty_colors"

# VSCode dynamic palette sync (JSONC-tolerant).
for vscode_settings in \
  "$HOME/.config/Code/User/settings.json" \
  "$HOME/.config/Code - OSS/User/settings.json"
do
  [ -f "$vscode_settings" ] || continue
  python3 - "$vscode_settings" "$bg" "$text" "$accent" "$muted" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
bg, text, accent, muted = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

raw = path.read_text(encoding="utf-8")

def strip_jsonc(s: str) -> str:
    # Remove // and /* */ comments.
    s = re.sub(r"//.*?$", "", s, flags=re.MULTILINE)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.DOTALL)
    # Remove trailing commas before } or ].
    s = re.sub(r",(\s*[}\]])", r"\1", s)
    return s

try:
    data = json.loads(strip_jsonc(raw))
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

cc = data.get("workbench.colorCustomizations")
if not isinstance(cc, dict):
    cc = {}

cc.update(
    {
        "editor.background": bg,
        "editor.foreground": text,
        "activityBar.background": bg,
        "activityBar.foreground": text,
        "statusBar.background": accent,
        "statusBar.foreground": bg,
        "sideBar.background": bg,
        "sideBar.foreground": text,
        "titleBar.activeBackground": bg,
        "titleBar.activeForeground": text,
        "tab.activeBackground": bg,
        "tab.activeForeground": text,
        "tab.inactiveForeground": muted,
    }
)

data["workbench.colorCustomizations"] = cc
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
done

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
