# Noxflow Setup TODO

Last updated: 2026-03-05

## Done

- [x] Add keybind cheat sheet overlay script (`hypr/scripts/hypr-binds.sh`)
- [x] Bind helper to `Super+F1` and `Super+Ctrl+/`
- [x] Improve launcher + quick-actions row hints (`Ctrl+1..0` for top 10)
- [x] Add media key wrappers for OSD-aware volume/brightness controls
- [x] Add startup hooks for `udiskie --tray` and `avizo-service`
- [x] Add Timeshift automation script + systemd timer units
- [x] Add SDDM login-theme setup script
- [x] Expand package manifests with debugging/learning tools and quality-of-life CLIs
- [x] Add launcher frequent-app mode + Ctrl+Tab view toggle
- [x] Add side-panel workspace workflow + workspace-9 logs helpers
- [x] Add weekly health-check script with PASS/FAIL + red flags + log output (`setup/weekly-health-check.sh`)
- [x] Add user timer setup for weekly health-check (`setup/configure-weekly-healthcheck.sh`)
- [x] Add ultra-fast app launcher mode (`launcher.sh --fast`) with cached rows
- [x] Split launcher/search binds (`Super+Space`, `Super+Shift+Space`, `Super+Ctrl+Space`)
- [x] Add scratchpad terminal + scratchpad notes workflows
- [x] Add notes folder helper + default editor MIME setup script
- [x] Add dynamic day/night sync helper (`dynamic-theme-sync.sh`)
- [x] Add fullscreen tabbed dev-cheatsheet overlay (`Super+.`) with searchable categories and clipboard copy (`hypr/scripts/dev-cheatsheet.sh`)
- [x] Add config-driven cheatsheet tabs under `~/.config/dev-cheatsheet` (bootstrapped from `hypr/dev-cheatsheet-defaults/*.yaml`)
- [x] Remove scratchpad keybinds/workspace rules to avoid stuck/hard-crash workflows; repoint notes shortcut to `open-notes.sh`
- [x] Add wallpaper source downloader/importer workflow (`setup/fetch-wallpaper-sources.sh`, `hypr/scripts/wallpaper-import.sh`)
- [x] Unify wallpaper pool handling across `~/Pictures/wallpaper` + `~/Pictures/Wallpapers` in rotation script
- [x] Upgrade wallpaper theme sync to real palette extraction and generate runtime color overlays for Waybar/SwayNC/Rofi/Eww
- [x] Add Kitty runtime wallpaper palette sync (`~/.cache/hypr/theme-colors-kitty.conf` + `kitty @ set-colors`)
- [x] Document wallpaper/theming workflow and tuning knobs (`docs/WALLPAPER_THEMING.md`)

## Next

- [ ] Run package installer to ensure new dependencies are present (`ttf-inter`, `smartmontools`, `nvme-cli`, `code`, `helix`)
- [ ] Reboot and verify SDDM noxflow theme readability on real login screen
- [ ] Capture fresh screenshots after blur/glass/animation tune and do one final spacing pass
