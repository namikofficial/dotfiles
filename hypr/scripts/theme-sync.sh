#!/usr/bin/env sh
set -eu

wall="${1:-}"

# Stable accent per-wallpaper (hash-based palette pick)
palettes="#7aa2f7 #9ece6a #bb9af7 #2ac3de #e0af68 #f7768e"
if [ -n "$wall" ] && command -v cksum >/dev/null 2>&1; then
  idx=$(printf '%s' "$wall" | cksum | awk '{print $1 % 6 + 1}')
else
  idx=1
fi
accent=$(printf '%s\n' $palettes | sed -n "${idx}p")

# Rofi theme sync
cat > "$HOME/.config/rofi/theme.rasi" <<ROFI
* {
    font: "JetBrainsMono Nerd Font 12";

    bg: #101320ee;
    bg-alt: #1a1f33ee;
    fg: #d8def5;
    fg-muted: #9aa5ce;
    accent: ${accent};
    good: #9ece6a;
    bad: #f7768e;

    border: 2px;
    radius: 14px;

    background-color: transparent;
    text-color: @fg;
}

window {
    location: center;
    anchor: center;
    width: 46%;
    border: @border;
    border-color: @accent;
    border-radius: @radius;
    background-color: @bg;
    padding: 8px;
}

mainbox {
    spacing: 12px;
    padding: 14px;
    background-color: transparent;
}

inputbar {
    children: [prompt, entry];
    spacing: 10px;
    padding: 10px;
    border-radius: 10px;
    background-color: @bg-alt;
}

prompt {
    text-color: @accent;
    background-color: transparent;
}

entry {
    text-color: @fg;
    placeholder-color: @fg-muted;
    background-color: transparent;
}

listview {
    lines: 12;
    columns: 1;
    fixed-height: false;
    spacing: 6px;
    cycle: true;
    dynamic: true;
    scrollbar: false;
    background-color: transparent;
}

element {
    padding: 8px 10px;
    border-radius: 10px;
    background-color: transparent;
    text-color: @fg-muted;
}

element normal.normal {
    background-color: transparent;
    text-color: @fg-muted;
}

element normal.urgent,
element selected.urgent {
    background-color: #3a2430;
    text-color: @bad;
}

element selected.normal {
    background-color: @good;
    text-color: #11131f;
}

element-text {
    text-color: inherit;
    background-color: transparent;
    vertical-align: 0.5;
}

element-icon {
    size: 1.15em;
    background-color: transparent;
    margin: 0 10px 0 0;
}

mode-switcher {
    spacing: 8px;
    background-color: transparent;
}

button {
    padding: 7px 11px;
    border-radius: 9px;
    background-color: @bg-alt;
    text-color: @fg-muted;
}

button selected {
    background-color: @accent;
    text-color: #11131f;
}
ROFI

# Dunst legacy fallback sync (if user runs dunst manually)
sed -i "s/^frame_color = .*/frame_color = \"${accent}\"/" "$HOME/.config/dunst/dunstrc" 2>/dev/null || true
sed -i "0,/^frame_color = .*/s//frame_color = \"${accent}\"/" "$HOME/.config/dunst/dunstrc" 2>/dev/null || true

# Wlogout accent sync
sed -i "s/border-color: #89b4fa;/border-color: ${accent};/" "$HOME/.config/wlogout/style.css" 2>/dev/null || true

pkill -x waybar >/dev/null 2>&1 || true
waybar >/dev/null 2>&1 &
