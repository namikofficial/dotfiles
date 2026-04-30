# Noxflow Setup TODO

Last updated: 2026-04-29

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
- [x] Upgrade wallpaper theme sync to real palette extraction and generate runtime color overlays for Rofi
- [x] Add Kitty runtime wallpaper palette sync (`~/.cache/hypr/theme-colors-kitty.conf` + `kitty @ set-colors`)
- [x] Add Hyprlock runtime palette sync (`~/.cache/hypr/theme-colors-hyprlock.conf` + sourced lock vars)
- [x] Add GTK3/GTK4 wallpaper palette overrides (`~/.config/gtk-3.0/gtk.css`, `~/.config/gtk-4.0/gtk.css`)
- [x] Add VSCode wallpaper palette merge into user settings (`workbench.colorCustomizations`)
- [x] Document wallpaper/theming workflow and tuning knobs (`docs/WALLPAPER_THEMING.md`)
- [x] Add Kitty startup dashboard banner with system/repo context and dedicated app-like tabs (Dashboard, Scratch, Logs, Repo, AI, Clipboard)
- [x] Switch notification helpers to the shell-native backend (`notif-center-toggle.sh`, `notif-dnd-toggle.sh`)
- [x] Add AI freeform (`raw`) mode — freeform prompt with no preset base prompt (`Super + Alt + 2`)
- [x] Add dynamic monitor layouts (`dynamic-up`, `dynamic-right`) with automatic workspace routing (workspaces 1–5 on laptop, 6–10 on first connected external display)
- [x] Enable system tray controls via applets; `nm-applet` and `blueman-applet` auto-start by default for menu-style Wi-Fi/Bluetooth controls
- [x] Change Tmux prefix from `Ctrl + A` to `Ctrl + Space`
- [x] Add `open-syncthing.sh` helper and Syncthing entry in quick-actions menu

## Next

- [ ] Run package installer to ensure new dependencies are present (`ttf-inter`, `smartmontools`, `nvme-cli`, `code`, `helix`)
- [ ] Reboot and verify SDDM noxflow theme readability on real login screen
- [ ] Capture fresh screenshots after blur/glass/animation tune and verify latest top-bar spacing pass
