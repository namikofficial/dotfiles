# Wallpaper + Theming Pipeline

## What happens on wallpaper change

`~/.config/hypr/scripts/set-wallpaper.sh` now does this on every change:

1. Picks from the handpicked wallpaper pool:
- `~/Pictures/wallpaper/handpicked/1080p`
- `~/Pictures/wallpaper/handpicked/4k`

2. Applies wallpaper with safer defaults:
- `WALLPAPER_RESIZE_MODE=fit` (default)
- `WALLPAPER_TRANSITION_TYPE=fade` (default)
- Clears frame before draw to avoid ghosting artifacts
- Flattens transparent PNG/WEBP to prevent old wallpaper bleed-through
- Builds a monitor-sized padded canvas first, so images are not cropped or stretched by default

3. Triggers sync:
- lockscreen wallpaper sync
- palette extraction from current wallpaper
- runtime color files for Rofi/Kitty/Hyprlock
- unified palette contract for wlogout, SDDM, clipboard, scratchpad, and Wayle
- GTK3/GTK4 override CSS generation
- VSCode dynamic workbench color update

## Runtime color files

Generated under `~/.cache/hypr/`:

- `theme-colors-rofi.rasi`
- `theme-colors-kitty.conf`
- `theme-colors-hyprlock.conf`
- `theme-palette.json`
- `theme-palette.env`
- `theme-colors-sddm.js`

The canonical palette exposes `bg`, `surface`, `surface_alt`, `text`,
`muted`, `accent`, `accent_soft`, `danger`, and `success`. Compatibility
aliases such as `bg_soft`, `accent2`, and `warn` remain available to older
hooks.

## App Hook Layer

`theme-sync.sh` also runs executable hooks from:
- `~/.config/hypr/scripts/theme-hooks.d/*.sh`

Each hook receives palette env vars (`THEME_BG`, `THEME_TEXT`, `THEME_ACCENT`, etc.), so additional utilities can be auto-themed without editing core scripts.

Current default hooks:
- `10-btop-theme.sh` -> generates/updates `~/.config/btop/themes/NoxflowDynamic.theme` and sets `color_theme = "NoxflowDynamic"`.
- `20-zathura-theme.sh` -> writes `~/.config/zathura/theme.generated` and auto-includes it from `~/.config/zathura/zathurarc`.
- `30-shell-tools-theme.sh` -> generates:
  - `~/.cache/hypr/theme-shell.zsh` (`FZF_DEFAULT_OPTS`, `BAT_THEME`, `LG_CONFIG_FILE`)
  - `~/.config/bat/themes/NoxflowDynamic.tmTheme`
  - `~/.config/lazygit/theme.generated.yml`
- `40-discord-theme.sh` -> generates Discord-family CSS theme files:
  - `~/.config/vesktop/themes/NoxflowDynamic.theme.css`
  - `~/.config/discord/themes/NoxflowDynamic.theme.css`
  - `~/.config/Vencord/themes/NoxflowDynamic.theme.css`
  - `~/.config/BetterDiscord/themes/NoxflowDynamic.theme.css`

Core UI consumers also read the generated palette directly:

- wlogout runtime CSS
- SDDM `palette.js` when the installed theme is writable or `sudo -n` is available
- clipboard browser and scratchpad dashboard GTK styles
- Wayle palette and notification surfaces

## Scripts

- Apply next wallpaper:
`~/.config/hypr/scripts/set-wallpaper.sh --next`

- Reload the current wallpaper-derived theme stack without changing wallpaper:
`~/.config/hypr/scripts/theme-pass.sh`

- Hyprland shortcuts:
  `Super + Shift + O` -> next wallpaper
  `Super + Ctrl + Shift + Y` -> reload theme, Kitty, Hyprland, panel, and caches

- Curate current rotating pool for your monitor ratio/resolution:
`~/.config/hypr/scripts/wallpaper-curate.sh ~/Pictures/wallpaper/handpicked`

- Add an image to the handpicked pool (creates 4k copy + 1080p LANCZOS variant):
`~/.config/hypr/scripts/wallpaper-add.sh <path-to-image>`

- List current pool and browse manually-curated sources:
`~/Documents/code/dotfiles/setup/wallpaper-handpicked.sh`

## Environment knobs

- `WALLPAPER_RESIZE_MODE` (`fit`, `crop`, `stretch`)
- `WALLPAPER_TRANSITION_TYPE` (default `fade`)
- `WALLPAPER_TRANSITION_FPS`
- `WALLPAPER_TRANSITION_DURATION`
- `WALLPAPER_TRANSITION_STEP`
- `WALLPAPER_DIRS` (colon-separated pool list; default: `~/Pictures/wallpaper/handpicked/{1080p,4k}`)
- `WALLPAPER_ROTATE_MODE` (`daily` default, or `interval`)
- `WALLPAPER_ROTATE_CHECK_INTERVAL` (seconds, daily mode check cadence, default `600`)
- `WALLPAPER_ROTATE_INTERVAL` (seconds, interval mode only, default `1800`)
- `WALLPAPER_ROTATE_STATE_FILE` (daily mode state file, default `~/.cache/hypr/wallpaper-last-rotate-date`)
- `WALLPAPER_CANVAS_MODE` (`blurpad` default, `solidpad`, `raw`)

## Notes

- Kitty dynamic colors require `kitty` remote control support in running sessions (`kitty @ set-colors -a ...`).
- Hyprlock reads `~/.cache/hypr/theme-colors-hyprlock.conf` via `source = ...` in `hypr/hyprlock.conf`.
- GTK overrides are written to:
  - `~/.config/gtk-3.0/gtk.css`
  - `~/.config/gtk-4.0/gtk.css`
- VSCode colors are merged into:
  - `~/.config/Code/User/settings.json`
- Optional external integrations (auto-run only if installed):
  - `wal` (pywal)
  - `matugen`
  - `pywalfox update` (Firefox)
- Discord/Vesktop dynamic theming is applied when the client theme directories are available.
- PrismLauncher uses `ApplicationTheme=system` in `~/.local/share/PrismLauncher/prismlauncher.cfg`; it follows the system/Qt theme rather than panel CSS.
- If you want absolutely no visual transition artifacts, set:
`WALLPAPER_TRANSITION_TYPE=none`

## Why colors were not updating earlier

- Dynamic palette files were being imported in lower-priority order in some theme files, so static defaults won.
- Fix applied: dynamic imports now override base defaults (Rofi).

## Toolkit Scope Clarification

- GTK currently has stable major lines `GTK2`, `GTK3`, `GTK4`.
- There is no mainstream `GTK5/6/7/8` stack to target today.
- Your setup now covers GTK3/4 + Qt5/6 + terminal/UI tools with hook extensibility.
