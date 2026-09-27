#!/usr/bin/env sh
set -eu

wall="${1:-}"
cache_dir="$HOME/.cache/hypr"
mkdir -p "$cache_dir"
hooks_dir="$HOME/.config/hypr/scripts/theme-hooks.d"
lock_file="${XDG_RUNTIME_DIR:-/tmp}/noxflow-theme-sync.lock"
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
opencode_theme_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/themes"
opencode_theme_file="$opencode_theme_dir/noxflow-dynamic.json"
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

# Serialize palette generations. Silently skipping a concurrent run lets the
# wallpaper pointer advance while applications retain the previous palette.
exec 9>"$lock_file"
if ! flock -w 15 9; then
  printf 'theme-sync: timed out waiting for palette lock: %s\n' "$lock_file" >&2
  exit 1
fi

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

# Read a nested key like "colors.surfaceCanvas" or "accent.hover".
read_nested() {
  top="$1"; sub="$2"
  jq -r --arg t "$top" --arg s "$sub" '.[$t][$s]' "$palette_json"
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
on_secondary="$(jq -r '.colors.onSecondary // .text' "$palette_json")"
on_tertiary="$(jq -r '.colors.onTertiary // .text' "$palette_json")"
on_danger="$(jq -r '.colors.onError // .text' "$palette_json")"

# Fine-grained surface ladder
surf_canvas="$(jq -r '.colors.surfaceCanvas // .bg' "$palette_json")"
surf_base="$(jq -r '.colors.surfaceBase // .surface' "$palette_json")"
surf1="$(jq -r '.colors.surface1 // .surface_alt' "$palette_json")"
surf2="$(jq -r '.colors.surface2 // .surface_alt' "$palette_json")"
surf3="$(jq -r '.colors.surface3 // .bg_soft' "$palette_json")"
surf_float="$(jq -r '.colors.surfaceFloating // .surface_alt' "$palette_json")"

# Tertiary / neutral
tertiary="$(jq -r '.colors.tertiary // .accent2' "$palette_json")"
neutral="$(jq -r '.colors.neutral // .muted' "$palette_json")"
success_container="$(jq -r '.colors.successContainer // .surface2' "$palette_json")"
danger_container="$(jq -r '.colors.errorContainer // .surface2' "$palette_json")"
info="$(jq -r '.colors.info // .accent2' "$palette_json")"
bright_black="$(jq -r '.colors.terminal.brightBlack // .muted' "$palette_json")"
bright_red="$(jq -r '.colors.terminal.brightRed // .colors.error // .danger' "$palette_json")"
bright_green="$(jq -r '.colors.terminal.brightGreen // .colors.success' "$palette_json")"
bright_yellow="$(jq -r '.colors.terminal.brightYellow // .colors.warning' "$palette_json")"
bright_blue="$(jq -r '.colors.terminal.brightBlue // .accent' "$palette_json")"
bright_magenta="$(jq -r '.colors.terminal.brightMagenta // .colors.tertiary' "$palette_json")"
bright_cyan="$(jq -r '.colors.terminal.brightCyan // .accent2' "$palette_json")"
bright_white="$(jq -r '.colors.terminal.brightWhite // .text' "$palette_json")"
vscode_ui_theme="$(jq -r '.scheme.mode | if . == "light" then "light" else "dark" end' "$palette_json")"
if [ "$vscode_ui_theme" = "light" ]; then
  vscode_ui_theme="vs-light"
  vscode_theme_type="light"
else
  vscode_ui_theme="vs-dark"
  vscode_theme_type="dark"
fi

# Accent interaction states
accent_hover="$(jq -r '.colors.accent.hover // .accent' "$palette_json")"
accent_pressed="$(jq -r '.colors.accent.pressed // .accent' "$palette_json")"
accent_focus="$(jq -r '.colors.accent.focus // .accent' "$palette_json")"

# Outline levels
outline_subtle="$(jq -r '.colors.outlineSubtle // .muted' "$palette_json")"
outline_default="$(jq -r '.colors.outline // .muted' "$palette_json")"
outline_strong="$(jq -r '.colors.outlineStrong // .text' "$palette_json")"

# State containers
warn_container="$(jq -r '.colors.warningContainer // .surface_alt' "$palette_json")"
danger_container="$(jq -r '.colors.errorContainer // .surface_alt' "$palette_json")"
info_container="$(jq -r '.colors.infoContainer // .surface_alt' "$palette_json")"

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
# Fine-grained surface ladder
THEME_SURF_CANVAS=$surf_canvas
THEME_SURF_BASE=$surf_base
THEME_SURF_1=$surf1
THEME_SURF_2=$surf2
THEME_SURF_3=$surf3
THEME_SURF_FLOAT=$surf_float
THEME_TERTIARY=$tertiary
THEME_NEUTRAL=$neutral
THEME_ACCENT_HOVER=$accent_hover
THEME_ACCENT_PRESSED=$accent_pressed
THEME_ACCENT_FOCUS=$accent_focus
THEME_OUTLINE_SUBTLE=$outline_subtle
THEME_OUTLINE=$outline_default
THEME_OUTLINE_STRONG=$outline_strong
EOF2

# OpenCode TUI theme follows the same generated wallpaper palette as Kitty.
# Keep both theme variants synchronized because the selected CLI mode is a
# user preference, while the palette itself is regenerated on wallpaper swaps.
mkdir -p "$opencode_theme_dir"
jq -n \
  --arg primary "$accent" --arg secondary "$accent2" --arg tertiary "$tertiary" \
  --arg danger "$danger" --arg warn "$warn" --arg success "$success" --arg info "$info" \
  --arg text "$text" --arg muted "$muted" --arg bg "$surf_canvas" \
  --arg panel "$surf_base" --arg element "$surf2" --arg border "$outline_default" \
  --arg border_subtle "$outline_subtle" --arg success_bg "$success_container" \
  --arg danger_bg "$danger_container" \
  'def both($value): {dark: $value, light: $value};
   {"$schema": "https://opencode.ai/theme.json", theme: {
     primary: both($primary), secondary: both($secondary), accent: both($tertiary),
     error: both($danger), warning: both($warn), success: both($success), info: both($info),
     text: both($text), textMuted: both($muted),
     background: both($bg), backgroundPanel: both($panel), backgroundElement: both($element),
     border: both($border), borderActive: both($primary), borderSubtle: both($border_subtle),
     diffAdded: both($success), diffRemoved: both($danger), diffContext: both($muted),
     diffHunkHeader: both($secondary), diffHighlightAdded: both($success),
     diffHighlightRemoved: both($danger), diffAddedBg: both($success_bg),
     diffRemovedBg: both($danger_bg), diffContextBg: both($panel),
     diffLineNumber: both($muted), diffAddedLineNumberBg: both($success_bg),
     diffRemovedLineNumberBg: both($danger_bg), markdownText: both($text),
     markdownHeading: both($primary), markdownLink: both($secondary),
     markdownLinkText: both($tertiary), markdownCode: both($success),
     markdownBlockQuote: both($muted), markdownEmph: both($warn),
     markdownStrong: both($primary), markdownHorizontalRule: both($border_subtle),
     markdownListItem: both($tertiary), markdownListEnumeration: both($info),
     markdownImage: both($secondary), markdownImageText: both($tertiary),
     markdownCodeBlock: both($panel), syntaxComment: both($muted),
     syntaxKeyword: both($primary), syntaxFunction: both($secondary),
     syntaxVariable: both($text), syntaxString: both($success),
     syntaxNumber: both($warn), syntaxType: both($info),
     syntaxOperator: both($tertiary), syntaxPunctuation: both($muted)
   }}' >"$opencode_theme_file"

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
    /* Surface hierarchy */
    bg: ${surf_canvas}ef;
    bg-alt: ${surf_float}ee;
    surface: ${surf_base}ef;
    surface1: ${surf1}ee;
    surface2: ${surf2}ee;
    surface3: ${surf3}ee;
    floating: ${surf_float}ef;

    /* Text */
    fg: ${text};
    fg-muted: ${muted};

    /* Accent hierarchy */
    accent: ${accent};
    accent2: ${accent2};
    accent3: ${tertiary};
    accent-hover: ${accent_hover};
    accent-pressed: ${accent_pressed};

    /* Semantic */
    good: ${success};
    bad: ${danger};
    warning: ${warn};

    /* Borders */
    border: ${outline_subtle};
    border-strong: ${outline_strong};
    separator: ${outline_subtle};
}
EOF2

cat >"$kitty_colors" <<EOF2
# Generated by theme-sync. Do not edit.

# Base
foreground ${text}
background ${surf_canvas}
selection_foreground ${on_primary}
selection_background ${accent}

# Cursor — primary accent
cursor ${accent}
cursor_text_color ${on_primary}

# URLs and borders
url_color ${tertiary}
active_border_color ${accent}
inactive_border_color ${surf2}
bell_border_color ${warn}

# Tabs
tab_bar_background ${surf_canvas}
active_tab_foreground ${on_primary}
active_tab_background ${accent}
inactive_tab_foreground ${muted}
inactive_tab_background ${surf2}

# Marker / search
mark1_foreground ${on_primary}
mark1_background ${accent}
mark2_foreground ${on_secondary}
mark2_background ${accent2}
mark3_foreground ${on_tertiary}
mark3_background ${tertiary}

# Standard ANSI 16 — mapped to semantic roles
color0  ${surf_canvas}   # black   → background canvas
color1  ${danger}        # red     → danger
color2  ${success}       # green   → success
color3  ${warn}         # yellow  → warning
color4  ${accent}       # blue    → primary accent
color5  ${tertiary}      # magenta → tertiary accent
color6  ${accent2}       # cyan    → secondary accent
color7  ${text}         # white   → primary text

# Bright ANSI 8 — higher-energy semantic variants
color8  ${bright_black}    # bright black → readable neutral
color9  ${bright_red}      # bright red → lifted danger
color10 ${bright_green}    # bright green → lifted success
color11 ${bright_yellow}   # bright yellow → lifted warning
color12 ${bright_blue}     # bright blue → lifted primary
color13 ${bright_magenta}  # bright magenta → lifted tertiary
color14 ${bright_cyan}     # bright cyan → lifted secondary
color15 ${bright_white}    # bright white → strongest text
EOF2

cat >"$hyprlock_colors" <<EOF2
# Generated by theme-sync. Do not edit.
\$lock_bg = rgb(${surf_canvas#\#})
\$lock_fg = rgb(${text#\#})
\$lock_accent = rgb(${accent#\#})
\$lock_secondary = rgb(${accent2#\#})
\$lock_tertiary = rgb(${tertiary#\#})
\$lock_surface = rgb(${surf_base#\#})
\$lock_surface2 = rgb(${surf2#\#})
\$lock_muted = rgb(${muted#\#})
\$lock_danger = rgb(${danger#\#})
\$lock_success = rgb(${success#\#})
\$lock_warning = rgb(${warn#\#})
EOF2

# Hyprland — full window and decoration color map.
cat >"$hyprland_colors" <<EOF2
-- Generated by theme-sync. Do not edit.
hl.config({
  general = {
    col = {
      active_border = {
        colors = { "rgba(${accent#\#}ff)", "rgba(${accent2#\#}ff)" },
        angle = 45,
      },
      inactive_border = "rgba(${outline_subtle#\#}cc)",
    },
  },
})
EOF2

# Generated adapters for tools that cannot read the canonical JSON directly.
# These live in the cache and are included by the user's structural config.
cat >"$tmux_colors" <<EOF2
# Generated by nox-theme. Do not edit.
# Surface hierarchy
set -g @theme_surface_canvas "$surf_canvas"
set -g @theme_surface "$surf_base"
set -g @theme_surface1 "$surf1"
set -g @theme_surface2 "$surf2"
set -g @theme_surface3 "$surf3"
set -g @theme_surface_float "$surf_float"

set -g status-style "bg=$surf_canvas,fg=$text"
set -g status-left-style "bg=$accent,fg=${on_primary}"
set -g status-right-style "bg=$surf_canvas,fg=$text"
set -g status-left "#[fg=$on_primary,bg=$accent,bold]  #S  #[fg=$accent,bg=$surf_base] #[fg=$text,bg=$surf_base]"
set -g status-right "#[fg=$muted] %a %d %b #[fg=$text]%H:%M "
set -g window-status-style "fg=$muted,bg=$surf_canvas"
set -g window-status-current-style "fg=$text,bg=$surf2,bold"
set -g window-status-activity-style "fg=$warn,bg=$surf_canvas"
set -g window-status-bell-style "fg=$danger,bg=$surf_canvas,bold"
set -g message-style "bg=$surf2,fg=$text,bold"
set -g message-command-style "bg=$surf2,fg=$text"
set -g pane-border-style "fg=$outline_subtle"
set -g pane-active-border-style "fg=$accent"
set -g mode-style "bg=$surf_float,fg=$text,bold"
set -g clock-mode-colour "$accent"
set -g pane-border-format " #[fg=$accent]#{pane_index}#[fg=$muted] · #{pane_current_command}#{?pane_active, #[fg=$success]◆,} "
EOF2

cat >"$nvim_colors" <<EOF2
-- Generated by nox-theme. Do not edit.
-- Surface ladder
vim.g.noxflow_surface_canvas   = "$surf_canvas"
vim.g.noxflow_surface          = "$surf_base"
vim.g.noxflow_surface1         = "$surf1"
vim.g.noxflow_surface2         = "$surf2"
vim.g.noxflow_surface3         = "$surf3"
vim.g.noxflow_surface_float    = "$surf_float"
-- Accent hierarchy
vim.g.noxflow_primary         = "$accent"
vim.g.noxflow_secondary        = "$accent2"
vim.g.noxflow_tertiary        = "$tertiary"
vim.g.noxflow_neutral          = "$neutral"
-- Text
vim.g.noxflow_text            = "$text"
vim.g.noxflow_text_muted      = "$muted"
-- Outline
vim.g.noxflow_outline         = "$outline_default"
vim.g.noxflow_outline_subtle  = "$outline_subtle"
vim.g.noxflow_outline_strong  = "$outline_strong"
-- Semantic
vim.g.noxflow_success         = "$success"
vim.g.noxflow_warning         = "$warn"
vim.g.noxflow_danger          = "$danger"
-- Wallpaper-derived terminal colors
vim.g.terminal_color_0 = "$surf_canvas"
vim.g.terminal_color_1 = "$danger"
vim.g.terminal_color_2 = "$success"
vim.g.terminal_color_3 = "$warn"
vim.g.terminal_color_4 = "$accent"
vim.g.terminal_color_5 = "$tertiary"
vim.g.terminal_color_6 = "$accent2"
vim.g.terminal_color_7 = "$text"
vim.g.terminal_color_8 = "$bright_black"
vim.g.terminal_color_9 = "$bright_red"
vim.g.terminal_color_10 = "$bright_green"
vim.g.terminal_color_11 = "$bright_yellow"
vim.g.terminal_color_12 = "$bright_blue"
vim.g.terminal_color_13 = "$bright_magenta"
vim.g.terminal_color_14 = "$bright_cyan"
vim.g.terminal_color_15 = "$bright_white"
-- Interaction states
vim.g.noxflow_accent_hover    = "$accent_hover"
vim.g.noxflow_accent_pressed  = "$accent_pressed"
vim.g.noxflow_accent_focus    = "$accent_focus"
EOF2

cat >"$vscode_colors" <<EOF2
{
  "name": "NoxFlow Dynamic",
  "type": "$vscode_theme_type",
  "colors": {
    "editor.background": "$surf_canvas",
    "editor.foreground": "$text",
    "editorGroupHeader.tabsBackground": "$surf_base",
    "editorLineNumber.foreground": "$muted",
    "editorLineNumber.activeForeground": "$text",
    "editorCursor.foreground": "$accent",
    "editor.selectionBackground": "${accent}33",
    "editor.findMatchBackground": "${accent}44",
    "editor.findMatchHighlightBackground": "${accent}22",
    "editorWidget.background": "$surf_float",
    "editorWidget.border": "$outline_default",
    "editorSuggestWidget.background": "$surf_float",
    "editorSuggestWidget.border": "$outline_subtle",
    "editorSuggestWidget.selectedBackground": "$surf2",
    "editorHoverWidget.background": "$surf_float",
    "editorHoverWidget.border": "$outline_subtle",
    "minimap.background": "$surf_canvas",
    "sideBar.background": "$surf_base",
    "sideBar.foreground": "$text",
    "sideBarSectionHeader.background": "$surf1",
    "activityBar.background": "$surf_canvas",
    "activityBar.foreground": "$text",
    "activityBar.activeBorder": "$accent",
    "statusBar.background": "$accent",
    "statusBar.foreground": "$on_primary",
    "statusBar.noFolderBackground": "$surf_base",
    "statusBar.debuggingBackground": "$danger",
    "statusBar.debuggingForeground": "$on_danger",
    "titleBar.activeBackground": "$surf2",
    "titleBar.activeForeground": "$text",
    "titleBar.inactiveBackground": "$surf1",
    "panel.background": "$surf_base",
    "panel.border": "$outline_subtle",
    "panelTitle.activeBorder": "$accent",
    "tab.activeBackground": "$surf_base",
    "tab.activeForeground": "$text",
    "tab.inactiveBackground": "$surf1",
    "tab.inactiveForeground": "$muted",
    "tab.border": "$outline_subtle",
    "scrollbarSlider.background": "${muted}40",
    "scrollbarSlider.hoverBackground": "${muted}66",
    "scrollbarSlider.activeBackground": "${accent}60",
    "focusBorder": "$accent",
    "input.background": "$surf2",
    "input.border": "$outline_subtle",
    "input.foreground": "$text",
    "input.placeholderForeground": "$muted",
    "button.background": "$accent",
    "button.foreground": "$on_primary",
    "button.hoverBackground": "$accent_hover",
    "button.secondaryBackground": "$surf2",
    "button.secondaryForeground": "$text",
    "dropdown.background": "$surf_float",
    "dropdown.border": "$outline_subtle",
    "dropdown.foreground": "$text",
    "list.hoverBackground": "$surf2",
    "list.activeSelectionBackground": "$surf2",
    "list.activeSelectionForeground": "$text",
    "list.focusBackground": "$surf1",
    "tree.indentGuidesStroke": "$outline_subtle",
    "gitDecoration.modifiedResourceForeground": "$accent",
    "gitDecoration.deletedResourceForeground": "$danger",
    "gitDecoration.addedResourceForeground": "$success",
    "gitDecoration.untrackedResourceForeground": "$tertiary",
    "problemsErrorIcon.foreground": "$danger",
    "problemsWarningIcon.foreground": "$warn",
    "problemsInfoIcon.foreground": "$accent",
    "terminal.ansiBlack": "$surf_canvas",
    "terminal.ansiRed": "$danger",
    "terminal.ansiGreen": "$success",
    "terminal.ansiYellow": "$warn",
    "terminal.ansiBlue": "$accent",
    "terminal.ansiMagenta": "$tertiary",
    "terminal.ansiCyan": "$accent2",
    "terminal.ansiWhite": "$text",
    "terminal.ansiBrightBlack": "$bright_black",
    "terminal.ansiBrightRed": "$bright_red",
    "terminal.ansiBrightGreen": "$bright_green",
    "terminal.ansiBrightYellow": "$bright_yellow",
    "terminal.ansiBrightBlue": "$bright_blue",
    "terminal.ansiBrightMagenta": "$bright_magenta",
    "terminal.ansiBrightCyan": "$bright_cyan",
    "terminal.ansiBrightWhite": "$bright_white"
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
  "contributes": { "themes": [{ "label": "NoxFlow Dynamic", "uiTheme": "$vscode_ui_theme", "path": "./themes/NoxFlow Dynamic-color-theme.json" }] }
}
EOF2
cp "$vscode_colors" "$vscode_theme_dir/themes/NoxFlow Dynamic-color-theme.json"

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cat >"$gtk3_css" <<EOF2
/* Generated by theme-sync. Do not edit. */
@define-color theme_bg_color ${surf_canvas};
@define-color theme_fg_color ${text};
@define-color theme_surface_color ${surf_base};
@define-color theme_surface_container_low ${surf_canvas};
@define-color theme_surface_container ${surf1};
@define-color theme_surface_container_high ${surf2};
@define-color theme_surface_container_highest ${surf3};
@define-color theme_selected_bg_color ${accent};
@define-color theme_selected_fg_color ${on_primary};
@define-color theme_primary_color ${accent};
@define-color theme_primary_container_color ${accent_soft};
@define-color theme_secondary_color ${accent2};
@define-color theme_tertiary_color ${tertiary};
@define-color theme_outline_color ${outline_default};
@define-color theme_outline_variant_color ${outline_subtle};
@define-color theme_success_color ${success};
@define-color theme_warning_color ${warn};
@define-color theme_danger_color ${danger};
@define-color theme_text_primary_color ${text};
@define-color theme_text_secondary_color ${muted};
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
      THEME_ON_PRIMARY="$on_primary" \
      THEME_ON_DANGER="$on_danger" \
      THEME_ACCENT_SOFT="$accent_soft" \
      THEME_SUCCESS="$success" \
      THEME_ACCENT2="$accent2" \
      THEME_WARN="$warn" \
      THEME_DANGER="$danger" \
      THEME_TERTIARY="$tertiary" \
      THEME_NEUTRAL="$neutral" \
      THEME_ACCENT_HOVER="$accent_hover" \
      THEME_ACCENT_PRESSED="$accent_pressed" \
      THEME_ACCENT_FOCUS="$accent_focus" \
      THEME_SURF_CANVAS="$surf_canvas" \
      THEME_SURF_BASE="$surf_base" \
      THEME_SURF_1="$surf1" \
      THEME_SURF_2="$surf2" \
      THEME_SURF_3="$surf3" \
      THEME_SURF_FLOAT="$surf_float" \
      THEME_OUTLINE_SUBTLE="$outline_subtle" \
      THEME_OUTLINE="$outline_default" \
      THEME_OUTLINE_STRONG="$outline_strong" \
      sh "$hook" >/dev/null 2>&1 || true
  done
fi
