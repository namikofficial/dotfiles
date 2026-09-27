# Reference Repositories

Pinned commits for architecture and feature inspiration. These are references,
not vendored dependencies. Record the studied commit and license so an idea can
be revisited without pretending that a moving `main` branch was reviewed.

## Current architecture references (studied 2026-09-16)

### AvengeMedia/DankMaterialShell
- **URL:** https://github.com/AvengeMedia/DankMaterialShell
- **Studied commit:** `6ecdd6d45d7222509a0040fda86fbe26fc41e35c` (`master`)
- **License:** MIT
- **Adopt:** Modules/Services/Widgets responsibility boundaries and explicit
  shell IPC surfaces; keep Noxd as this repository's backend.
- **Do not copy:** provider implementations or the full shell/backend.

### WerWolv/noctalia-shell
- **URL:** https://github.com/WerWolv/noctalia-shell
- **Studied commit:** `5dc9a2f47c72d8a388022be0fee0f6798dfa8fe4` (`main`)
- **License:** MIT
- **Adopt:** quiet-by-default presentation and dedicated semantic surfaces.

### caelestia-dots/shell
- **URL:** https://github.com/caelestia-dots/shell
- **Studied commit:** `0f1435a2f5f0c6ad25a2858f282eee1a0453d8b0` (`main`)
- **License:** GPL-3.0
- **Adopt:** fluid geometry transitions and module boundaries as inspiration;
  no source is copied into this repository.

### material-foundation/material-color-utilities
- **URL:** https://github.com/material-foundation/material-color-utilities
- **Studied commit:** `5b3618b16fdc3825e21d5679bafd144662088ea1` (`main`)
- **License:** Apache-2.0
- **Adopt:** future HCT/Material dynamic-scheme adapter boundary. The current
  compiler keeps a Pillow-only deterministic fallback until the dependency is
  deliberately packaged.

### InioX/matugen
- **URL:** https://github.com/InioX/matugen
- **Studied commit:** `519e4a4bffdc78adbdc65f7882ce999d99a074c7` (`main`)
- **License:** GPL-2.0
- **Adopt:** template-oriented adapter concept only; it is not automatically
  co-run with `nox-theme.py`.

## Deep Study

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

### adi-chan/monochrome-os
- **URL:** https://github.com/adi-chan/monochrome-os
- **Steal:** hold-to-open radial shortcut wheel with editable slots
- **Avoid:** emoji-as-icons as primary production icon system

### yayuuu/hyprland-scroll-overview
- **URL:** https://github.com/yayuuu/hyprland-scroll-overview
- **Pinned:** (check latest commit)
- **Decision (2026-07-31):** ADOPTED as the primary window/workspace navigator.
  Replaces the QML Overview. ABI-breaking — rebuild after every Hyprland
  upgrade (`hyprpm update && hyprpm enable scrolloverview`, or source build).
  See `docs/shell-redesign/02-reference-analysis.md` for verified dispatchers,
  Lua config, gestures, and submap. Previously listed as "Do NOT adopt".

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
