# Wallpaper + Theming Pipeline

## What happens on wallpaper change

`~/.config/hypr/scripts/set-wallpaper.sh` now does this on every change:

1. Picks from both pools:
- `~/Pictures/wallpaper`
- `~/Pictures/Wallpapers`

2. Applies wallpaper with safer defaults:
- `WALLPAPER_RESIZE_MODE=crop` (default)
- `WALLPAPER_TRANSITION_TYPE=fade` (default)
- Clears frame before draw to avoid ghosting artifacts
- Flattens transparent PNG/WEBP to prevent old wallpaper bleed-through

3. Triggers sync:
- lockscreen wallpaper sync
- palette extraction from current wallpaper
- runtime color files for Waybar/SwayNC/Rofi/Eww/Kitty

## Runtime color files

Generated under `~/.cache/hypr/`:

- `theme-colors-waybar.css`
- `theme-colors-swaync.css`
- `theme-colors-rofi.rasi`
- `theme-colors-eww.scss`
- `theme-colors-kitty.conf`
- `theme-palette.json`

## Scripts

- Apply next wallpaper:
`~/.config/hypr/scripts/set-wallpaper.sh --next`

- Curate current rotating pool for your monitor ratio/resolution:
`~/.config/hypr/scripts/wallpaper-curate.sh ~/Pictures/wallpaper`

- Copy compatible wallpapers from source packs into rotating pool:
`~/.config/hypr/scripts/wallpaper-copy-from-sources.sh ~/Pictures/wallpaper-sources ~/Pictures/wallpaper`

- Download/update source packs:
`~/Documents/code/dotfiles/setup/fetch-wallpaper-sources.sh`

## Environment knobs

- `WALLPAPER_RESIZE_MODE` (`crop`, `fit`, `stretch`)
- `WALLPAPER_TRANSITION_TYPE` (default `fade`)
- `WALLPAPER_TRANSITION_FPS`
- `WALLPAPER_TRANSITION_DURATION`
- `WALLPAPER_TRANSITION_STEP`
- `WALLPAPER_DIRS` (colon-separated pool list)
- `WALL_SOURCE_ROOT` (for source downloader)
- `WALL_GIT_TIMEOUT_SECONDS`
- `WALL_UPDATE_EXISTING=1` to pull existing clones

## Notes

- Kitty dynamic colors require `kitty` remote control support in running sessions (`kitty @ set-colors -a ...`).
- If you want absolutely no visual transition artifacts, set:
`WALLPAPER_TRANSITION_TYPE=none`
