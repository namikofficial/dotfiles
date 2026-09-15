#!/usr/bin/env sh
set -eu

wall="${1:-}"
cache_dir="$HOME/.cache/hypr"
mkdir -p "$cache_dir"
hooks_dir="$HOME/.config/hypr/scripts/theme-hooks.d"
lock_dir="${XDG_RUNTIME_DIR:-/tmp}/noxflow-theme-sync.lock"
skip_wayle_palette="${NOXFLOW_SKIP_WAYLE_PALETTE:-0}"

palette_json="$cache_dir/theme-palette.json"
palette_env="$cache_dir/theme-palette.env"
sddm_palette="$cache_dir/theme-colors-sddm.js"
rofi_colors="$cache_dir/theme-colors-rofi.rasi"
kitty_colors="$cache_dir/theme-colors-kitty.conf"
hyprlock_colors="$cache_dir/theme-colors-hyprlock.conf"
hyprland_colors="$cache_dir/theme-colors-hyprland.lua"
nvim_colors="$cache_dir/theme-nvim.lua"
tmux_colors="$cache_dir/theme-colors-tmux.conf"
vscode_colors="$cache_dir/noxflow-vscode-color-theme.json"
vscode_theme_dir="$HOME/.vscode/extensions/noxflow.dynamic-theme-0.0.1"
wayle_palette_stamp="$cache_dir/wayle-palette.current"
gtk3_css="$HOME/.config/gtk-3.0/gtk.css"
gtk4_css="$HOME/.config/gtk-4.0/gtk.css"
kitty_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

kitty_remote_all() {
  command -v kitty >/dev/null 2>&1 || return 0
  for sock in "$kitty_runtime_dir"/kitty-control*; do
    [ -S "$sock" ] || continue
    kitty @ --to "unix:$sock" "$@" >/dev/null 2>&1 || true
  done
}

cleanup_lock() {
  rmdir "$lock_dir" >/dev/null 2>&1 || true
}

if ! mkdir "$lock_dir" >/dev/null 2>&1; then
  exit 0
fi
trap cleanup_lock EXIT HUP INT TERM

if [ -z "$wall" ] || [ ! -f "$wall" ]; then
  if [ -f "$HOME/.cache/current-wallpaper" ]; then
    wall="$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null || true)"
  fi
fi

if [ -z "$wall" ] || [ ! -f "$wall" ]; then
  exit 0
fi

if [ -x "$HOME/.config/hypr/scripts/nox-theme.py" ]; then
  # One canonical compiler owns wallpaper sampling, policy, and validation.
  "$HOME/.config/hypr/scripts/nox-theme.py" "$wall" "$palette_json" --validate
else
  # Compatibility fallback for installations made before the compiler was
  # linked. Keep this path deterministic and remove it once re-bootstrap is
  # complete on the workstation.
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

def lift_contrast(seed_rgb, bg_rgb, target_ratio, mix=0.12, max_steps=24):
    """Raise contrast against bg without risking unbounded loops."""
    color = seed_rgb
    for _ in range(max_steps):
        if contrast_ratio(color, bg_rgb) >= target_ratio:
            break
        nxt = blend(color, (255, 255, 255), mix)
        if nxt == color:
            break
        color = nxt
    return color

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
surface = blend(bg, (255, 255, 255), 0.08)
bg_soft = blend(bg, (255, 255, 255), 0.15)

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

accent = lift_contrast(accent, bg, 2.35, mix=0.12, max_steps=24)
accent2 = lift_contrast(accent2, bg, 2.05, mix=0.10, max_steps=24)

if hue_distance(
    colorsys.rgb_to_hsv(*(c / 255 for c in accent))[0],
    colorsys.rgb_to_hsv(*(c / 255 for c in accent2))[0],
) < 0.10:
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in accent2))
    h = (h + 0.16) % 1.0
    accent2 = tuple(int(round(channel * 255)) for channel in colorsys.hsv_to_rgb(h, max(s, 0.30), max(v, 0.70)))

light_text = (245, 238, 233)
dark_text = (42, 36, 40)

def text_score(candidate):
    return min(
        contrast_ratio(candidate, bg),
        contrast_ratio(candidate, bg_soft),
        contrast_ratio(candidate, surface),
    )

text = light_text
muted = (175, 162, 161)
warn = (255, 166, 110)
danger = (255, 117, 127)
surface_alt = bg_soft
accent_soft = blend(accent, surface, 0.36)
success = accent2

out_data = {
    "bg": to_hex(bg),
    "bg_soft": to_hex(bg_soft),
    "surface": to_hex(surface),
    "surface_alt": to_hex(surface_alt),
    "text": to_hex(text),
    "muted": to_hex(muted),
    "accent": to_hex(accent),
    "accent_soft": to_hex(accent_soft),
    "success": to_hex(success),
    "accent2": to_hex(accent2),
    "warn": to_hex(warn),
    "danger": to_hex(danger),
}
out.write_text(json.dumps(out_data, indent=2), encoding="utf-8")
PY
fi

read_color() {
  key="$1"
  jq -r --arg k "$key" '.[$k]' "$palette_json"
}

bg="$(read_color bg)"
bg_soft="$(read_color bg_soft)"
surface="$(read_color surface)"
surface_alt="$(read_color surface_alt)"
text="$(read_color text)"
muted="$(read_color muted)"
accent="$(read_color accent)"
accent_soft="$(read_color accent_soft)"
success="$(read_color success)"
accent2="$(read_color accent2)"
warn="$(read_color warn)"
danger="$(read_color danger)"
on_primary="$(jq -r '.colors.onPrimary // .text' "$palette_json")"

cat >"$palette_env" <<EOF2
# Generated by theme-sync. Do not edit.
THEME_BG=$bg
THEME_BG_SOFT=$bg_soft
THEME_SURFACE=$surface
THEME_SURFACE_ALT=$surface_alt
THEME_TEXT=$text
THEME_MUTED=$muted
THEME_ACCENT=$accent
THEME_ACCENT_SOFT=$accent_soft
THEME_SUCCESS=$success
THEME_ACCENT2=$accent2
THEME_WARN=$warn
THEME_DANGER=$danger
EOF2

cat >"$sddm_palette" <<EOF2
// Generated by theme-sync. Do not edit.
.pragma library
var bg = "$bg"
var surface = "$surface"
var surfaceAlt = "$surface_alt"
var text = "$text"
var muted = "$muted"
var accent = "$accent"
var accentSoft = "$accent_soft"
var danger = "$danger"
var success = "$success"
EOF2

sddm_theme_dir="/usr/share/sddm/themes/noxflow"
if [ -d "$sddm_theme_dir" ]; then
  if [ -w "$sddm_theme_dir" ]; then
    install -m644 "$sddm_palette" "$sddm_theme_dir/palette.js" 2>/dev/null || true
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n install -m644 "$sddm_palette" "$sddm_theme_dir/palette.js" 2>/dev/null || true
  fi
fi

cat >"$rofi_colors" <<EOF2
* {
    bg: ${bg}ef;
    bg-alt: ${bg_soft}ee;
    fg: ${text};
    fg-muted: ${muted};
    accent: ${accent};
    good: ${success};
    bad: ${danger};
}
EOF2

cat >"$kitty_colors" <<EOF2
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
inactive_tab_background ${surface_alt}
color0  ${bg}
color1  ${danger}
color2  ${accent2}
color3  ${warn}
color4  ${accent}
color5  ${accent2}
color6  ${accent}
color7  ${text}
color8  ${muted}
color9  ${danger}
color10 ${accent2}
color11 ${warn}
color12 ${accent}
color13 ${accent2}
color14 ${accent}
color15 ${text}
EOF2

cat >"$hyprlock_colors" <<EOF2
\$lock_bg = rgb(${bg#\#})
\$lock_fg = rgb(${text#\#})
\$lock_accent = rgb(${accent#\#})
EOF2

# Hyprland active/inactive border colours sourced at reload time.
cat >"$hyprland_colors" <<EOF2
-- Generated by theme-sync. Do not edit.
hl.config({
  general = {
    col = {
      active_border = {
        colors = { "rgba(${accent#\#}ff)", "rgba(${accent2#\#}ff)" },
        angle = 45,
      },
      inactive_border = "rgba(${surface#\#}cc)",
    },
  },
})
EOF2

# Generated adapters for tools that cannot read the canonical JSON directly.
# These live in the cache and are included by the user's structural config.
cat >"$tmux_colors" <<EOF2
# Generated by nox-theme. Do not edit.
set -g status-style "bg=$bg,fg=$text"
set -g message-style "bg=$surface_alt,fg=$text,bold"
set -g message-command-style "bg=$surface_alt,fg=$text"
set -g pane-border-style "fg=$muted"
set -g pane-active-border-style "fg=$accent"
set -g mode-style "bg=$accent_soft,fg=$text,bold"
set -g clock-mode-colour "$accent"
set -g pane-border-format " #[fg=$accent]#{pane_index}#[fg=$muted] · #{pane_current_command}#{?pane_active, #[fg=$success]◆,} "
set -g status-left "#[fg=$bg,bg=$accent,bold]  #S #[fg=$accent,bg=$surface]#[fg=$text,bg=$surface]  ? help · s sessions · p projects · a actions · t scratch · D diagnostics #[fg=$surface,bg=$bg]"
set -g window-status-style "fg=$muted,bg=$bg"
set -g window-status-format "#[fg=$muted]#{window_index} #W#{?window_activity_flag,#[fg=$warn] •,}"
set -g window-status-current-style "fg=$on_primary,bg=$accent,bold"
set -g window-status-current-format "#[fg=$accent,bg=$bg]#[fg=$on_primary,bg=$accent,bold] #{window_index} #W#{?window_zoomed_flag, ⛶,} #[fg=$accent,bg=$bg]"
set -g status-right "#[fg=$success]CPU #{cpu_percentage}#[fg=$muted] · #[fg=$accent2]BAT #{battery_icon} #{battery_percentage}#[fg=$muted] · #[fg=$accent2]%a %d %b %H:%M "
EOF2

cat >"$nvim_colors" <<EOF2
-- Generated by nox-theme. Do not edit.
return {
  background = "$bg",
  surface = "$surface",
  surface_alt = "$surface_alt",
  foreground = "$text",
  muted = "$muted",
  primary = "$accent",
  secondary = "$accent2",
  success = "$success",
  warning = "$warn",
  danger = "$danger",
  outline = "$muted",
}
EOF2

cat >"$vscode_colors" <<EOF2
{
  "name": "NoxFlow Dynamic",
  "type": "dark",
  "colors": {
    "editor.background": "$bg",
    "editor.foreground": "$text",
    "editorGroupHeader.tabsBackground": "$surface",
    "sideBar.background": "$surface",
    "sideBar.foreground": "$text",
    "activityBar.background": "$bg",
    "activityBar.foreground": "$text",
    "statusBar.background": "$accent",
    "statusBar.foreground": "$on_primary",
    "titleBar.activeBackground": "$surface_alt",
    "titleBar.activeForeground": "$text",
    "panel.border": "$muted",
    "focusBorder": "$accent",
    "terminal.ansiBlue": "$accent",
    "terminal.ansiGreen": "$success",
    "terminal.ansiYellow": "$warn",
    "terminal.ansiRed": "$danger"
  }
}
EOF2

# VS Code discovers themes from extensions. Keep this generated extension
# isolated from the user's settings.json; after the one-time selection of
# “NoxFlow Dynamic”, future theme passes only replace this generated file.
mkdir -p "$vscode_theme_dir/themes"
cat >"$vscode_theme_dir/package.json" <<'EOF2'
{
  "name": "noxflow-dynamic-theme",
  "displayName": "NoxFlow Dynamic Theme",
  "version": "0.0.1",
  "publisher": "noxflow",
  "engines": { "vscode": ">=1.80.0" },
  "contributes": { "themes": [{ "label": "NoxFlow Dynamic", "uiTheme": "vs-dark", "path": "./themes/NoxFlow Dynamic-color-theme.json" }] }
}
EOF2
cp "$vscode_colors" "$vscode_theme_dir/themes/NoxFlow Dynamic-color-theme.json"

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cat >"$gtk3_css" <<EOF2
@define-color theme_bg_color ${bg};
@define-color theme_fg_color ${text};
@define-color theme_selected_bg_color ${accent};
@define-color theme_selected_fg_color ${bg};
EOF2
cp "$gtk3_css" "$gtk4_css"

printf '%s\n' "$accent" >"$cache_dir/current-accent"

apply_wayle_palette() {
  command -v wayle >/dev/null 2>&1 || return 0
  case "$skip_wayle_palette" in
    1 | true | yes | on)
      return 0
      ;;
  esac

  palette_sig="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$bg" "$surface" "$surface_alt" "$text" "$muted" "$accent" "$accent_soft" "$success" "$danger" "$warn")"
  if [ -f "$wayle_palette_stamp" ] && [ "$(cat "$wayle_palette_stamp" 2>/dev/null || true)" = "$palette_sig" ]; then
    return 0
  fi

  wayle config set styling.palette.bg "\"$bg\"" >/dev/null 2>&1 || return 0
  wayle config set styling.palette.surface "\"$surface\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.elevated "\"$surface_alt\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.fg "\"$text\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.fg-muted "\"$muted\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.primary "\"$accent\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.red "\"$danger\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.yellow "\"$warn\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.green "\"$success\"" >/dev/null 2>&1 || true
  wayle config set styling.palette.blue "\"$accent_soft\"" >/dev/null 2>&1 || true
  printf '%s\n' "$palette_sig" >"$wayle_palette_stamp"

  if systemctl --user is-active --quiet wayle.service 2>/dev/null || pgrep -x wayle >/dev/null 2>&1; then
    wayle panel restart >/dev/null 2>&1 || true
  fi
}

apply_wayle_palette

kitty_remote_all set-colors -a "$kitty_colors"

# VS Code consumes its own generated theme/extension; never rewrite a user's
# settings file as a side effect of switching wallpaper.

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
      THEME_SURFACE_ALT="$surface_alt" \
      THEME_TEXT="$text" \
      THEME_MUTED="$muted" \
      THEME_ACCENT="$accent" \
      THEME_ACCENT_SOFT="$accent_soft" \
      THEME_SUCCESS="$success" \
      THEME_ACCENT2="$accent2" \
      THEME_WARN="$warn" \
      THEME_DANGER="$danger" \
      sh "$hook" >/dev/null 2>&1 || true
  done
fi
