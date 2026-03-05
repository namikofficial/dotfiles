#!/usr/bin/env sh
set -eu

[ -n "${THEME_BG:-}" ] || exit 0
[ -n "${THEME_TEXT:-}" ] || exit 0
[ -n "${THEME_ACCENT:-}" ] || exit 0
[ -n "${THEME_ACCENT2:-}" ] || exit 0

css_content="$(cat <<EOF2
:root {
  --nox-bg: ${THEME_BG};
  --nox-bg-soft: ${THEME_BG_SOFT:-$THEME_BG};
  --nox-surface: ${THEME_SURFACE:-$THEME_BG_SOFT};
  --nox-text: ${THEME_TEXT};
  --nox-muted: ${THEME_MUTED:-$THEME_TEXT};
  --nox-accent: ${THEME_ACCENT};
  --nox-accent2: ${THEME_ACCENT2};
  --nox-warn: ${THEME_WARN:-$THEME_ACCENT};
  --nox-danger: ${THEME_DANGER:-$THEME_ACCENT2};

  --background-primary: var(--nox-bg) !important;
  --background-secondary: var(--nox-bg-soft) !important;
  --background-secondary-alt: var(--nox-surface) !important;
  --background-tertiary: var(--nox-bg-soft) !important;
  --background-floating: var(--nox-surface) !important;
  --text-normal: var(--nox-text) !important;
  --text-muted: var(--nox-muted) !important;
  --text-link: var(--nox-accent) !important;
  --brand-experiment: var(--nox-accent) !important;
  --brand-experiment-560: var(--nox-accent2) !important;
}
EOF2
)"

write_theme() {
  target="$1"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$css_content" > "$target"
}

# Standard theme directories (future-proof if app gets installed later).
write_theme "$HOME/.config/vesktop/themes/NoxflowDynamic.theme.css"
write_theme "$HOME/.config/discord/themes/NoxflowDynamic.theme.css"
write_theme "$HOME/.config/Vencord/themes/NoxflowDynamic.theme.css"
write_theme "$HOME/.config/BetterDiscord/themes/NoxflowDynamic.theme.css"

# If QuickCSS exists, keep it in sync.
if [ -f "$HOME/.config/vesktop/settings/quickCss.css" ]; then
  write_theme "$HOME/.config/vesktop/settings/quickCss.css"
fi
if [ -f "$HOME/.config/Vencord/settings/quickCss.css" ]; then
  write_theme "$HOME/.config/Vencord/settings/quickCss.css"
fi
