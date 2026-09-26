#!/usr/bin/env sh
set -eu

[ -n "${THEME_BG:-}" ] || exit 0
[ -n "${THEME_TEXT:-}" ] || exit 0
[ -n "${THEME_ACCENT:-}" ] || exit 0
[ -n "${THEME_ACCENT2:-}" ] || exit 0

css_content="$(
  cat <<EOF2
:root {
  /* Surface hierarchy */
  --nox-canvas:    ${THEME_SURF_CANVAS:-$THEME_BG};
  --nox-base:      ${THEME_SURF_BASE:-$THEME_SURFACE};
  --nox-surface1:  ${THEME_SURF_1:-$THEME_BG_SOFT};
  --nox-surface2:  ${THEME_SURF_2:-$THEME_SURFACE_ALT};
  --nox-surface3:  ${THEME_SURF_3:-$THEME_BG_SOFT};
  --nox-floating:  ${THEME_SURF_FLOAT:-$THEME_SURFACE_ALT};

  /* Text */
  --nox-text:      ${THEME_TEXT};
  --nox-muted:     ${THEME_MUTED:-$THEME_TEXT};

  /* Accent hierarchy */
  --nox-accent:    ${THEME_ACCENT};
  --nox-accent2:   ${THEME_ACCENT2};
  --nox-tertiary:  ${THEME_TERTIARY:-$THEME_ACCENT2};
  --nox-hover:     ${THEME_ACCENT_HOVER:-$THEME_ACCENT};
  --nox-pressed:   ${THEME_ACCENT_PRESSED:-$THEME_ACCENT};

  /* Semantic */
  --nox-success:   ${THEME_SUCCESS};
  --nox-warn:     ${THEME_WARN:-$THEME_ACCENT};
  --nox-danger:    ${THEME_DANGER:-$THEME_ACCENT2};

  /* Borders */
  --nox-outline:        ${THEME_OUTLINE:-$THEME_MUTED};
  --nox-outline-subtle: ${THEME_OUTLINE_SUBTLE:-$THEME_MUTED};
  --nox-outline-strong: ${THEME_OUTLINE_STRONG:-$THEME_TEXT};

  /* Discord-specific mapping */
  --background-primary:   var(--nox-canvas) !important;
  --background-secondary: var(--nox-base) !important;
  --background-tertiary: var(--nox-surface1) !important;
  --background-floating: var(--nox-floating) !important;
  --background-overlay:  var(--nox-surface2) !important;
  --background-modifier-accent: var(--nox-accent) !important;

  --text-normal:       var(--nox-text) !important;
  --text-muted:       var(--nox-muted) !important;
  --text-link:         var(--nox-accent) !important;

  --header-primary:    var(--nox-text) !important;
  --header-secondary:  var(--nox-muted) !important;

  --interactive-normal: var(--nox-text) !important;
  --interactive-hover: var(--nox-hover) !important;
  --interactive-active: var(--nox-pressed) !important;
  --interactive-muted: var(--nox-muted) !important;

  --brand-experiment:  var(--nox-accent) !important;
  --brand-experiment-560: var(--nox-accent2) !important;

  --focus-primary:     var(--nox-accent) !important;
  --mention-foreground: var(--nox-accent) !important;
  --mention-background: color-mix(in srgb, var(--nox-accent) 15%, transparent) !important;

  --status-success:   var(--nox-success) !important;
  --status-danger:    var(--nox-danger) !important;
  --status-warning:   var(--nox-warn) !important;
  --status-possible-running: var(--nox-success) !important;

  --modals-backdrop:  rgba(0, 0, 0, 0.6) !important;
}
EOF2
)"

write_theme() {
  target="$1"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$css_content" >"$target"
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
