# Wallpaper + Theming Pipeline

## What happens on wallpaper change

`~/.config/hypr/scripts/set-wallpaper.sh` now does this on every change:

1. Picks from the curated wallpaper pools:
- `~/Pictures/wallpaper/1080p`
- `~/Pictures/wallpaper/4k`
- `~/Pictures/wallpaper`
- `~/Pictures/Wallpapers`

2. Applies wallpaper with safer defaults:
- `WALLPAPER_RESIZE_MODE=fit` (default)
- `WALLPAPER_TRANSITION_TYPE=fade` (default)
- Clears frame before draw to avoid ghosting artifacts
- Flattens transparent PNG/WEBP to prevent old wallpaper bleed-through
- Builds a monitor-sized padded canvas first, so images are not cropped or stretched by default

3. Triggers sync:
- lockscreen wallpaper sync
- palette extraction from current wallpaper
- runtime color files for Waybar/SwayNC/Rofi/Eww/Kitty/Hyprlock
- GTK3/GTK4 override CSS generation
- VSCode dynamic workbench color update

## Runtime color files

Generated under `~/.cache/hypr/`:

- `theme-colors-waybar.css`
- `theme-colors-swaync.css`
- `theme-colors-rofi.rasi`
- `theme-colors-eww.scss`
- `theme-colors-kitty.conf`
- `theme-colors-hyprlock.conf`
- `theme-palette.json`

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

## Scripts

- Apply next wallpaper:
`~/.config/hypr/scripts/set-wallpaper.sh --next`

- Curate current rotating pool for your monitor ratio/resolution:
`~/.config/hypr/scripts/wallpaper-curate.sh ~/Pictures/wallpaper`

- Copy compatible wallpapers from source packs into the curated 1080p/4k pool:
`~/.config/hypr/scripts/wallpaper-copy-from-sources.sh ~/Pictures/wallpaper-sources ~/Pictures/wallpaper`

- Download/update source packs:
`~/Documents/code/dotfiles/setup/fetch-wallpaper-sources.sh`

## Environment knobs

- `WALLPAPER_RESIZE_MODE` (`fit`, `crop`, `stretch`)
- `WALLPAPER_TRANSITION_TYPE` (default `fade`)
- `WALLPAPER_TRANSITION_FPS`
- `WALLPAPER_TRANSITION_DURATION`
- `WALLPAPER_TRANSITION_STEP`
- `WALLPAPER_DIRS` (colon-separated pool list)
- `WALLPAPER_ROTATE_MODE` (`daily` default, or `interval`)
- `WALLPAPER_ROTATE_CHECK_INTERVAL` (seconds, daily mode check cadence, default `600`)
- `WALLPAPER_ROTATE_INTERVAL` (seconds, interval mode only, default `1800`)
- `WALLPAPER_ROTATE_STATE_FILE` (daily mode state file, default `~/.cache/hypr/wallpaper-last-rotate-date`)
- `WALLPAPER_CANVAS_MODE` (`blurpad` default, `solidpad`, `raw`)
- `WALL_SOURCE_ROOT` (for source downloader)
- `WALL_GIT_TIMEOUT_SECONDS`
- `WALL_UPDATE_EXISTING=1` to pull existing clones

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
- Qt apps are forced to the Qt theming stack via Hyprland env:
  - `QT_QPA_PLATFORMTHEME=qt6ct`
  - `QT_STYLE_OVERRIDE=kvantum`
- Discord/Vesktop dynamic theming is not applied automatically yet (needs client theme plugin layer).
- PrismLauncher uses `ApplicationTheme=system` in `~/.local/share/PrismLauncher/prismlauncher.cfg`; it will follow system/Qt theme, not Waybar CSS.
- If you want absolutely no visual transition artifacts, set:
`WALLPAPER_TRANSITION_TYPE=none`

## Why colors were not updating earlier

- Dynamic palette files were being imported in lower-priority order in some theme files, so static defaults won.
- Fix applied: dynamic imports now override base defaults (Waybar/SwayNC/Rofi/Eww).
- `swaync-client -rs` could block sync; it now runs with a timeout so downstream updates (including Kitty/VSCode) continue.

## Toolkit Scope Clarification

- GTK currently has stable major lines `GTK2`, `GTK3`, `GTK4`.
- There is no mainstream `GTK5/6/7/8` stack to target today.
- Your setup now covers GTK3/4 + Qt5/6 + terminal/UI tools with hook extensibility.
