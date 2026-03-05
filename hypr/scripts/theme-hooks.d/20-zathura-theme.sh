#!/usr/bin/env sh
set -eu

[ -n "${THEME_BG:-}" ] || exit 0
[ -n "${THEME_TEXT:-}" ] || exit 0
[ -n "${THEME_ACCENT:-}" ] || exit 0
[ -n "${THEME_ACCENT2:-}" ] || exit 0

conf_dir="$HOME/.config/zathura"
main_rc="$conf_dir/zathurarc"
theme_rc="$conf_dir/theme.generated"
include_line="include $theme_rc"

mkdir -p "$conf_dir"

cat > "$theme_rc" <<EOF2
set recolor true
set recolor-keephue true
set default-bg "${THEME_BG}"
set default-fg "${THEME_TEXT}"
set statusbar-bg "${THEME_BG_SOFT:-$THEME_BG}"
set statusbar-fg "${THEME_TEXT}"
set inputbar-bg "${THEME_BG_SOFT:-$THEME_BG}"
set inputbar-fg "${THEME_TEXT}"
set notification-bg "${THEME_BG_SOFT:-$THEME_BG}"
set notification-fg "${THEME_TEXT}"
set notification-error-bg "${THEME_DANGER:-$THEME_ACCENT}"
set notification-error-fg "${THEME_TEXT}"
set notification-warning-bg "${THEME_WARN:-$THEME_ACCENT2}"
set notification-warning-fg "${THEME_TEXT}"
set highlight-color "${THEME_ACCENT}"
set highlight-active-color "${THEME_ACCENT2}"
set completion-bg "${THEME_BG_SOFT:-$THEME_BG}"
set completion-fg "${THEME_TEXT}"
set completion-highlight-bg "${THEME_ACCENT}"
set completion-highlight-fg "${THEME_BG}"
set recolor-lightcolor "${THEME_BG}"
set recolor-darkcolor "${THEME_TEXT}"
EOF2

if [ ! -f "$main_rc" ]; then
  printf '%s\n' "$include_line" > "$main_rc"
elif ! grep -Fqx "$include_line" "$main_rc"; then
  printf '\n%s\n' "$include_line" >> "$main_rc"
fi
