#!/usr/bin/env sh
set -eu

# Inputs are provided by theme-sync.sh via environment variables.
cache_dir="${THEME_CACHE_DIR:-$HOME/.cache/hypr}"
theme_dir="$HOME/.config/btop/themes"
theme_file="$theme_dir/NoxflowDynamic.theme"
conf_file="$HOME/.config/btop/btop.conf"

[ -n "${THEME_BG:-}" ] || exit 0
[ -n "${THEME_TEXT:-}" ] || exit 0
[ -n "${THEME_ACCENT:-}" ] || exit 0
[ -n "${THEME_ACCENT2:-}" ] || exit 0
[ -n "${THEME_WARN:-}" ] || exit 0
[ -n "${THEME_DANGER:-}" ] || exit 0

mkdir -p "$theme_dir"

cat > "$theme_file" <<EOF2
theme[Noxflow Dynamic]

main_bg="${THEME_BG}"
main_fg="${THEME_TEXT}"
title="${THEME_ACCENT}"
hi_fg="${THEME_ACCENT}"
selected_bg="${THEME_BG_SOFT:-$THEME_BG}"
selected_fg="${THEME_TEXT}"
inactive_fg="${THEME_MUTED:-$THEME_TEXT}"
graph_text="${THEME_ACCENT2}"
meter_bg="${THEME_BG_SOFT:-$THEME_BG}"
proc_misc="${THEME_ACCENT2}"
cpu_box="${THEME_ACCENT}"
mem_box="${THEME_ACCENT2}"
net_box="${THEME_WARN}"
proc_box="${THEME_ACCENT}"
div_line="${THEME_BG_SOFT:-$THEME_BG}"
temp_start="${THEME_ACCENT2}"
temp_mid="${THEME_WARN}"
temp_end="${THEME_DANGER}"
cpu_start="${THEME_ACCENT2}"
cpu_mid="${THEME_ACCENT}"
cpu_end="${THEME_WARN}"
free_start="${THEME_ACCENT2}"
free_mid="${THEME_ACCENT}"
free_end="${THEME_WARN}"
cached_start="${THEME_ACCENT2}"
cached_mid="${THEME_ACCENT}"
cached_end="${THEME_WARN}"
available_start="${THEME_ACCENT2}"
available_mid="${THEME_ACCENT}"
available_end="${THEME_WARN}"
used_start="${THEME_WARN}"
used_mid="${THEME_DANGER}"
used_end="${THEME_DANGER}"
download_start="${THEME_ACCENT2}"
download_mid="${THEME_ACCENT}"
download_end="${THEME_WARN}"
upload_start="${THEME_ACCENT2}"
upload_mid="${THEME_ACCENT}"
upload_end="${THEME_WARN}"
process_start="${THEME_ACCENT2}"
process_mid="${THEME_ACCENT}"
process_end="${THEME_WARN}"
EOF2

mkdir -p "$(dirname "$conf_file")"
if [ ! -f "$conf_file" ]; then
  cat > "$conf_file" <<EOF2
color_theme = "NoxflowDynamic"
EOF2
elif grep -q '^color_theme *=.*' "$conf_file"; then
  sed -i 's/^color_theme *=.*/color_theme = "NoxflowDynamic"/' "$conf_file" || true
else
  printf '\ncolor_theme = "NoxflowDynamic"\n' >> "$conf_file"
fi

printf '%s\n' "$theme_file" > "$cache_dir/current-btop-theme"
