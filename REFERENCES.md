# Reference Repositories

Pinned commits for architecture and feature inspiration. See `PLAN.md` for the steal mapping.

## Deep Study

### caelestia-dots/shell
- **URL:** https://github.com/caelestia-dots/shell
- **Pinned:** (check latest commit)
- **Steal:** drawer morph geometry, component/module/service split, shell IPC, morphing animation transitions
- **Ignore:** visual identity, dependency set

### caelestia-dots/caelestia
- **URL:** https://github.com/caelestia-dots/caelestia
- **Steal:** central config, reusable QML components, clean separation between shell and dotfiles

### enhaoswen/Tide-island
- **URL:** https://github.com/enhaoswen/Tide-island
- **Pinned:** (check latest commit)
- **Steal:** contextual state priority, compact island for media/timer/recording/mic/system changes, IPC-controlled user service
- **Ignore:** full dependency set

### Ronin-CK/QuickSnip
- **URL:** https://github.com/Ronin-CK/QuickSnip
- **Pinned:** (check latest commit)
- **Steal:** unified capture pipeline (screenshot → selection → OCR → translation → search → annotation → smart actions)

## Skim

### end-4/dots-hyprland
- **URL:** https://github.com/end-4/dots-hyprland
- **Steal:** AI integration patterns (configurable endpoint, streaming), Material surface treatment, screen translation pipeline
- **Ignore:** full workflow, opinionated app choices

### samjoshuadud/waylandar
- **URL:** https://github.com/samjoshuadud/waylandar
- **Steal:** Google Calendar sync architecture (gcalcli integration, background polling, reminders), ICS parser
- **Caution:** OAuth credentials outside repo (add to `.gitignore`)

### Hyde-project/hyde
- **URL:** https://github.com/Hyde-project/hyde
- **Steal:** theme packaging, import/export, preview cards for visual identity switching

### ilyamiro/nixos-configuration
- **URL:** https://github.com/ilyamiro/nixos-configuration
- **Steal:** navbar, calendar inspiration, non-invasive shell layered over compositor config

## Deferred (visual/mood-board only)

### AvengeMedia/DankMaterialShell
- **URL:** https://github.com/AvengeMedia/DankMaterialShell
- **Note:** Defer full provider/plugin architecture until noxd hits a ceiling

### adi-chan/monochrome-os
- **URL:** https://github.com/adi-chan/monochrome-os
- **Steal:** hold-to-open radial shortcut wheel with editable slots
- **Avoid:** emoji-as-icons as primary production icon system

### yayuuu/hyprland-scroll-overview
- **URL:** https://github.com/yayuuu/hyprland-scroll-overview
- **Note:** Do NOT adopt — Hyprland ABI-breaking plugin. QML-only approach in Overview already functional.

### binnewbs/arch-hyprland
- **URL:** https://github.com/binnewbs/arch-hyprland
- **Note:** Visual recipes (wallpaper, Matugen, Waybar/Rofi styling) — collage-style architecture, don't reproduce

### Cybersnake223/Hypr
- **URL:** https://github.com/Cybersnake223/Hypr
- **Note:** Visual recipes only, Super+Space tool aesthetic

### pctrade/end4-pC
- **URL:** https://github.com/pctrade/end4-pC
- **Note:** Skim sidebar/widget concepts; don't depend on another person's shell repo

### zacoons/rivendell-hyprdots
- **URL:** https://codeberg.org/zacoons/rivendell-hyprdots
- **Note:** Theatrical notification animations, border treatments — defer until Phase 5

### Reddit posts (mood board)
- Morphing animations: https://www.reddit.com/r/hyprland/comments/1rleoku/morphing_animations_in_ui/
- Dashboard/weather: https://www.reddit.com/r/hyprland/comments/1rj737s/a_beautiful_dashboard_with_weather_custom_modules/
- Rice screenshot: https://www.reddit.com/r/hyprland/comments/1v6xz7w/rice_screenshot/
- Updated rice: https://www.reddit.com/r/hyprland/comments/1v70yfe/updated_my_rice/
- Caelestia Quickshare: https://www.reddit.com/r/hyprland/comments/1v4sifd/caelestia_quickshare/
- Dynamic Island: https://www.reddit.com/r/hyprland/comments/1ulhnr3/hyprland_i_made_a_dynamic_island_on_hyprland/
- Google Calendar widget: https://www.reddit.com/r/hyprland/comments/1ua9b24/finally_a_google_calendar_widget/
- Lens alternative: https://www.reddit.com/r/hyprland/comments/1rozo12/coming_soon_google_lens_alternative_for_linux/

## Optional Tools (install, don't wire into shell)

### khoj-ai/khoj
- **URL:** https://github.com/khoj-ai/khoj
- **Note:** Self-hosted AI second brain. Optional external service — never a startup dependency.

### rtk-ai/rtk
- **URL:** https://github.com/rtk-ai/rtk
- **Note:** CLI proxy reducing LLM token consumption by 60-90%. Optional dev tool, not part of shell.
