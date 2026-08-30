[![DMS 1.0 "The Dark Knight" Released | Dank Linux](https://images.openai.com/static-rsc-4/MlokuOXSE770nTMqbi9yE__ydR_PMAbFTOY5z7kbGElbeVnPBMThCM6_UEafNnJRC7SgBNBGbY7JJymKhJvvNzC365BJ94Vb3eLBgEaMZVD7xGF9Y2LPYOGe1NLQk_pMH3264nz6YJd-4uLQrv05xxlyoXyLv1PlE-56_xR9qtU?purpose=inline)](https://danklinux.com/blog/v1-release?utm_source=chatgpt.com)

# Verdict

Your dotfiles do **not** need more scripts, menus, widgets, or keybinds.

They need to become a **desktop shell product**.

At present, the repository already contains:

- A modular Hyprland configuration.
    
- Wayle as a panel shell.
    
- Rofi launchers and settings interfaces.
    
- Python/GTK utilities.
    
- Separate notification, clipboard, scratchpad, dashboard, wallpaper and theme scripts.
    
- A settings schema and profile system.
    
- Local-AI and project-workbench integrations.
    
- A large bootstrap and health-check layer.
    

The problem is that these features are implemented as separate systems. Your Wayle bar alone invokes numerous polling scripts, some every 600 milliseconds or five seconds, and contains hard-coded `/home/namik` paths.

Your startup script has effectively become an improvised service manager. It warms caches, launches daemons, manages duplicate processes, starts applets, applies settings, controls plugins and starts wallpaper watchers.

The rebuild should therefore follow this rule:

> **One shell, one state service, one design system, one settings model and one coherent interaction language.**

# The Qt/GTK question

Do not make “no Qt or GTK” the goal.

Quickshell itself uses Qt/QML, and most of the strongest projects you supplied—including Caelestia, end-4, Tide Island, Monochrome OS and DankMaterialShell—use Quickshell or Qt/QML for their shell interfaces. ([GitHub](https://github.com/caelestia-dots/shell "GitHub - caelestia-dots/shell: A fluid, morphing shell for your Linux desktop · GitHub"))

What you actually want is:

- **Wayland-native shell surfaces**
    
- A single UI framework for everything you own
    
- Shared animations, typography, spacing and components
    
- Event-driven system state
    
- GTK and Qt theme adapters for third-party applications
    
- No visible mixture of Rofi, GTK windows, tray applets and unrelated popup styles
    

A genuinely toolkit-free shell would require writing your own Wayland layer-shell renderer, text stack, image pipeline, input handling and animation system in Rust or C++. That would turn your dotfiles project into a desktop-environment engineering project.

## Recommended architecture

Use:

- **Quickshell/QML** for the visible desktop shell
    
- **Rust** for a compiled state and automation daemon
    
- **Hyprland Lua configuration** for compositor behaviour
    
- **systemd user services** for lifecycle management
    
- **TOML** for user configuration
    
- **Unix socket or D-Bus IPC** between the shell, daemon and CLI
    

This gives you Quickshell’s fluid interfaces while keeping shell scripts and repeated polling out of the UI.

# What each inspiration should contribute

| Reference                                         | Take from it                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Do not copy                                                                                                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Caelestia + Caelestia Shell + Quickshare post** | Quickshare post/flow, Morphing drawers, clean separation between shell and general dotfiles, central configuration, reusable QML components and shell IPC. Caelestia already separates components, modules, services, utilities and its shell entrypoint. ([GitHub](https://github.com/caelestia-dots/shell "GitHub - caelestia-dots/shell: A fluid, morphing shell for your Linux desktop · GitHub"))                                                                               | Do not clone the complete visual identity or inherit all dependencies.                                                                           |
| **DankMaterialShell**                             | The strongest architectural reference: Quickshell frontend, compiled backend, system monitoring, launcher, control centre, notifications, clipboard, calendar, settings and plugin/provider concepts. ([GitHub](https://github.com/AvengeMedia/DankMaterialShell "GitHub - AvengeMedia/DankMaterialShell: Desktop shell for wayland compositors built with Quickshell & GO, optimized for niri, hyprland, sway, MangoWC, labwc, and MiracleWM. · GitHub"))                           | Do not build an equally broad public desktop environment before your personal workflow is stable.                                                |
| **end-4 dots**                                    | i want definateely want AI integration just like they have it and Material-inspired design system, live workspace overview, screen translation, AI integration and usability-first shell design. ([GitHub](https://github.com/end-4/dots-hyprland "GitHub - end-4/dots-hyprland: Usability-first dotfiles · GitHub"))                                                                                                                                                                | Avoid copying its entire opinionated workflow but that is much better than my workflow in dotfiles.                                              |
| **end4-pC**                                       | Sidebar, wegetis and notifaitonbar etc and The concept of selectable shell configurations and personal shell variants. ([GitHub](https://github.com/pctrade/end4-pC "GitHub - pctrade/end4-pC: Custom end4 · GitHub"))                                                                                                                                                                                                                                                               | Avoid making your shell dependent on another person’s shell repository.                                                                          |
| **Tide Island + Dynamic Island post**             | i also want Tide Island + Dynamic Island post in my fotfiles so take a look here more carefully A compact contextual surface for media, timers, recording, microphone, system changes and temporary activities. Tide demonstrates a Quickshell island controlled through IPC and a user service. ([GitHub](https://github.com/enhaoswen/Tide-island "GitHub - enhaoswen/Tide-island: Tide Island is a smooth, lightweight, and flexible interactive island for Hyprland. · GitHub")) | Do not turn it into a permanent information dump for everything but make it better than the post.                                                |
| **Monochrome OS**                                 | Visual restraint and its hold-to-open radial shortcut wheel with editable slots.                                                                                                                                                                                                                                                                                                                                                                                                     | Avoid emoji-based iconography as the primary production icon system.                                                                             |
| **hyprland-scroll-overview**                      | Native-feeling workspace overview with scrolling and compositor integration. ([GitHub](https://github.com/yayuuu/hyprland-scroll-overview "GitHub - yayuuu/hyprland-scroll-overview: Scroll overview plugin, just like niri. Based on scroll-overview branch of hyprexpo. · GitHub"))                                                                                                                                                                                                | Do not make the desktop unusable whenever a Hyprland plugin breaks after an ABI update.                                                          |
| **Morphing animations post**                      | This is the best one and i want exactly sometiing like this, Continuous transformation between button, popup, island and panel states instead of windows simply appearing. The author also notes that Quickshell provides more fluidity but has a meaningful learning and resource cost. ([Reddit](https://www.reddit.com/r/hyprland/comments/1rleoku/morphing_animations_in_ui/ "Morphing animations in UI : r/hyprland"))                                                          | Avoid animations that delay frequent actions.                                                                                                    |
| **ilyamiro Nix configuration**                    | Keep the shell non-invasive and layered over compositor configuration so it can eventually support more than one compositor. ([GitHub](https://github.com/ilyamiro/nixos-configuration "GitHub - ilyamiro/nixos-configuration: Configuration for my NixOS setup · GitHub"))                                                                                                                                                                                                          | Do not migrate your entire workstation to NixOS merely for its shell structure but take a look at navbar and calendar etc for inspiration.       |
| **Dashboard/weather post**                        | I loved this but i also want google claander integration if possible , A keyboard-driven personal dashboard with weather, schedules, system state and custom modules. ([Reddit](https://www.reddit.com/r/hyprland/comments/1rj737s/a_beautiful_dashboard_with_weather_custom_modules/ "A beautiful dashboard with weather / custom modules for hyprland : r/hyprland"))                                                                                                              |                                                                                                                                                  |
| **QuickSnip + Lens alternative post**             | I also want exact this thing in my dotfiles as well, One capture workflow containing screenshot selection, OCR, translation, search, annotation and smart actions. ([GitHub](https://github.com/Ronin-CK/QuickSnip "GitHub - Ronin-CK/QuickSnip: ⚡ Lightweight Wayland OCR & Google Lens utility built with Quickshell. · GitHub"))                                                                                                                                                  | Do not create separate shortcuts and applications for every capture action.                                                                      |
| **Waylandar + Calendar widget post**              | Compact agenda widget, expanded calendar dashboard, background syncing and reminder surfaces. It currently supports multiple calendar sources but remains primarily read-only. ([GitHub](https://github.com/samjoshuadud/waylandar "GitHub - samjoshuadud/waylandar: A standalone Wayland calendar widget and dashboard for Hyprland and Sway. Seamlessly syncs with Google Calendar, Nextcloud, iCloud, and ICS feeds. · GitHub"))                                                  | Do not embed Google OAuth credentials directly into your public dotfiles.                                                                        |
| **Rivendell**                                     | I also want these type of Theatrical notification animations and panels, border treatments and occasional personality. Its direct Codeberg page was blocked during inspection, so I used indexed descriptions rather than assuming implementation details. ([Lemmy.World](https://lemmy.world/post/34737259?utm_source=chatgpt.com "How I won Hyprland's 4th ricing competition - Zacoons - Lemmy.World"))                                                                           | Do not animate every routine notification.                                                                                                       |
| **HyDE**                                          | Theme packaging, theme previews and the ability to switch complete visual identities. ([GitHub](https://github.com/Hyde-project/hyde "GitHub - HyDE-Project/HyDE: HyDE, your Development Environment ️ · GitHub"))                                                                                                                                                                                                                                                                   | Do not use its installer or allow upstream updates to overwrite personal configuration.                                                          |
| **binnewbs and Cybersnake223**                    | Wallpaper, Matugen, Waybar/Rofi styling and individual visual recipes. ([GitHub](https://github.com/binnewbs/arch-hyprland "GitHub - binnewbs/arch-hyprland: My personal hyprland rice dotfiles · GitHub"))                                                                                                                                                                                                                                                                          | These are examples of collage-style dotfiles. Do not reproduce their architecture but their super+space tool is great and great looking as well. |
| **Updated-rice and rice-screenshot posts**        | Visual references for density, spacing and composition. Several Reddit media pages did not render through the crawler, so they should remain mood-board references rather than architectural sources.                                                                                                                                                                                                                                                                                | Do not copy a screenshot without understanding interaction behaviour.                                                                            |
| **RTK**                                           | Optional developer command compression for AI agents and noisy CLI outputs. It is a Rust binary intended to reduce repetitive command output. ([GitHub](https://github.com/rtk-ai/rtk "GitHub - rtk-ai/rtk: CLI proxy that reduces LLM token consumption by 60-90% on common dev commands. Single Rust binary, zero dependencies · GitHub"))                                                                                                                                         | Do not route normal interactive shell commands through it automatically.                                                                         |
| **Khoj**                                          | On-demand personal knowledge retrieval, document search and local-agent capabilities. ([GitHub](https://github.com/khoj-ai/khoj "GitHub - khoj-ai/khoj: Your AI second brain. Self-hostable. Get answers from the web or your docs. Build custom agents, schedule automations, do deep research. Turn any online or local LLM into your personal, autonomous AI (gpt, claude, gemini, llama, qwen, mistral). Get started - free. · GitHub"))                                         | Do not make a heavy AI service mandatory for basic desktop startup.                                                                              |

# The new desktop concept

I would keep the existing **NoxFlow** identity and rebuild it as a cohesive shell.

## 1. Minimal top bar

The top bar should show only:

- Workspaces
    
- Current application or project
    
- Clock
    
- Temporary media indicator
    
- Network(Wifi/Bluettooth), sound and battery cluster, cpu and ram usage
    
- Notification state
    

Remove permanent `LOG`, project, Git, task, AI and update labels from the bar. Your current configuration puts too much workstation telemetry into a narrow persistent surface.

Those details belong in expandable surfaces.

## 2. Nox Island

A centred morphing live-activity surface:

- Volume and brightness changes
    
- Now playing
    
- Microphone active
    
- Screen recording
    
- Screenshot processing
    
- File transfer progress
    
- Timer
    
- AI task completion
    
- Build or test result
    
- VPN/network transition
    
- Battery warnings
    

It should normally be invisible and expand only when state changes.

## 3. Left-side workspace surface

Opened with `Super + Tab`:

- Live workspace thumbnails
    
- Window search
    
- Drag or keyboard movement between workspaces
    
- Named workspace scenes
    
- Project indicators
    
- Sidecar and scratchpad windows
    
- Optional scroll-overview integration
    

Use the Hyprland plugin where compatible, with a shell-based fallback after compositor upgrades.

## 4. Right-side control centre

Opened with `Super + A`:

- Wi-Fi
    
- Bluetooth
    
- Audio devices and mixer
    
- Brightness
    
- Power profile
    
- Night light
    
- Screen layout
    
- VPN
    
- Do Not Disturb
    
- Recording controls
    
- Syncthing status
    
- Recent system warnings
    

Once this reaches feature parity, remove `nm-applet`, `blueman-applet`, Avizo/SwayOSD and ordinary tray-based control workflows.

## 5. Notification centre

Opened with `Super + N`:

- Grouped notifications by application
    
- Actions(like copy notification etc etc)
    
- Read/unread state
    
- DND scheduling
    
- Clear by group
    
- Notification history
    
- Calendar reminders
    
- Build and local-agent results
    

Notifications should use the same card, motion and typography system as the rest of the shell.

## 6. Universal command centre

`Super + Space` becomes the single launcher for:

- Applications
    
- Open windows
    
- Files
    
- Settings
    
- Shell actions
    
- Projects
    
- Git repositories
    
- Clipboard history
    
- Calculator
    
- Commands
    
- AI questions
    
- Documentation
    
- Calendar events
    

Rofi can remain temporarily as an emergency fallback, but it should stop being the visible foundation of the desktop.

## 7. Capture workflow

`Super + Shift + S`:

1. Select area, window, monitor or colour.
    
2. Show one result surface.
    
3. Choose Copy, Save, Annotate, OCR, Translate, Search Image or Share.
    
4. Display completion in Nox Island.
    

This replaces separate screenshot, OCR and image-search scripts. and it should automatically save the ss instead of opening two windows back to back after taking a screen shot

## 8. Dashboard

`Super + D`:

- Today’s agenda
    
- Weather
    
- Current project
    
- Git status
    
- Active task
    
- Recent files
    
- System health
    
- Local AI status
    
- Package updates
    
- Syncthing and backup state
    
- Quick actions
    

This should be a deliberate full-screen workspace—not a giant bar dropdown.

# Backend structure

Create a Rust daemon named `noxd`.

It should subscribe to events instead of repeatedly invoking commands.

### Providers

- Hyprland socket events
    
- PipeWire/WirePlumber
    
- MPRIS media
    
- NetworkManager D-Bus
    
- BlueZ D-Bus
    
- UPower
    
- systemd user manager
    
- Notifications
    
- Clipboard history
    
- Calendar
    
- Weather
    
- Syncthing
    
- Git/project workbench
    
- Local AI runtime
    
- Package update cache
    

### Interfaces

- `noxctl status`
    
- `noxctl shell toggle control-center`
    
- `noxctl setting set appearance.profile focus`
    
- `noxctl capture ocr`
    
- `noxctl project switch nox-billings`
    
- `noxctl doctor`
    
- `noxctl events`
    

The QML shell consumes structured state. It should not contain shell commands such as `brightnessctl | awk`, absolute home paths or five-second polling loops.

# Proposed repository structure

```text
dotfiles/
├── shell/
│   └── noxflow/
│       ├── Shell.qml
│       ├── components/
│       │   ├── buttons/
│       │   ├── cards/
│       │   ├── icons/
│       │   ├── inputs/
│       │   └── motion/
│       ├── surfaces/
│       │   ├── bar/
│       │   ├── island/
│       │   ├── launcher/
│       │   ├── overview/
│       │   ├── control-center/
│       │   ├── notifications/
│       │   ├── dashboard/
│       │   ├── capture/
│       │   ├── lockscreen/
│       │   └── radial-menu/
│       ├── services/
│       ├── models/
│       └── theme/
├── core/
│   └── noxd/
│       ├── Cargo.toml
│       └── src/
│           ├── providers/
│           ├── ipc/
│           ├── config/
│           ├── events/
│           └── main.rs
├── cli/
│   └── noxctl/
├── compositor/
│   └── hypr/
│       ├── hyprland.lua
│       └── conf/
├── config/
│   ├── default.toml
│   ├── keybindings.toml
│   └── profiles/
│       ├── laptop.toml
│       ├── docked.toml
│       ├── focus.toml
│       ├── gaming.toml
│       └── safe-gpu.toml
├── theme/
│   ├── tokens.toml
│   ├── templates/
│   │   ├── qml/
│   │   ├── hyprland/
│   │   ├── gtk/
│   │   ├── qt/
│   │   ├── kitty/
│   │   ├── nvim/
│   │   └── sddm/
│   └── generated/
├── apps/
│   ├── kitty/
│   ├── nvim/
│   ├── tmux/
│   ├── zsh/
│   ├── atuin/
│   └── chrome/
├── systemd/
│   └── user/
├── install/
│   ├── bootstrap.sh
│   ├── manifest.toml
│   └── packages/
│       ├── core.txt
│       ├── desktop.txt
│       ├── development.txt
│       ├── gaming.txt
│       └── optional.txt
├── tests/
├── docs/
└── legacy/                 # Temporary during migration
```

# What should be removed

Do not delete everything immediately. Move replacements through a controlled deprecation process.

## Remove after feature parity

- `wayle/`
    
- Wayle status wrappers and polling modules
    
- Rofi interfaces duplicated by the new launcher
    
- Python/GTK dashboard interfaces
    
- Python/GTK clipboard interfaces
    
- Standalone settings windows
    
- Separate notification-menu scripts
    
- Avizo or SwayOSD
    
- `wlogout`
    
- `nm-applet` and `blueman-applet`
    
- Duplicate wallpaper/theme watchers
    
- Duplicate screenshot and OCR entrypoints
    
- Hard-coded `/home/namik` paths
    
- Manual process-deduplication logic in `startup.sh`
    
- Generated caches and runtime logs accidentally living near configuration
    
- Competing overview systems once the fallback strategy is proven
    
- Duplicate keybindings that open the same action through three or four combinations
    

Your package manifest also installs several overlapping tools—for example both Swappy and Satty, tmux and Zellij, Neovim and Helix, multiple graphical audio tools and multiple applet-based controls. These should become explicit package profiles rather than default requirements and remove the duplicates and make dolfin the default for file exporlfe instead of yazi and other files also needs default for opening applciaiton as well

## Keep and improve

- Modular Hyprland Lua configuration
    
- UWSM environment management
    
- Neovim(whole things need a rework and improvement it us broken and usbale right now), Kitty, Zsh, tmux and Atuin configurations
    
- Existing health-check philosophy
    
- Package manifests
    
- Settings profiles
    
- NVIDIA recovery logic(right now everything is working perfectly)
    
- Monitor profile logic
    
- Project/workbench functionality
    
- Local AI runtime
    
- Private scripts as a separate dependency
    
- Generated keybinding documentation
    
- Safe bootstrap and backup behaviour
    

# One design system

Use one semantic token source:

```toml
[appearance]
mode = "dark"
density = "comfortable"
radius = 14
motion = "fluid"
transparency = "balanced"

[color]
background = "#090B10"
surface = "#11141C"
surface_container = "#181C27"
surface_high = "#222838"
text = "#F2F5FA"
text_muted = "#9EA8B8"
primary = "#8FA8FF"
secondary = "#7CE0D3"
success = "#7ADFA4"
warning = "#F2C66D"
danger = "#FF7993"
outline = "#303749"
```

Generate adapters for:

- Quickshell
    
- Hyprland
    
- GTK 3/4
    
- Qt 5/6 and Kvantum
    
- Kitty
    
- Neovim
    
- Chrome
    
- SDDM
    
- Hyprlock
    

The shell can support three visual profiles:

1. **Focus** — subdued, nearly monochrome.
    
2. **Ambient** — wallpaper-derived palette.
    
3. **Performance** — reduced blur and motion.
    

This is better than changing every colour whenever the wallpaper rotates.

# Keybinding cleanup

The current repository exposes many overlapping access paths. The replacement should have one memorable route per major surface.

| Action             | Binding             |
| ------------------ | ------------------- |
| Universal launcher | `Super + Space`     |
| Workspace overview | `Super + Tab`       |
| Control centre     | `Super + A`         |
| Notifications      | `Super + N`         |
| Dashboard          | `Super + D`         |
| Clipboard          | `Super + V`         |
| Capture centre     | `Super + Shift + S` |
| Settings           | `Super + ,`         |
| Scratch workspace  | `Super + ``         |
| Window search      | `Super + W`         |
| Keybinding guide   | `Super + F1`        |
| Lock               | `Super + Escape`    |

Everything else should be discoverable through the launcher or contextual menus.

# Migration sequence

## Phase 0 — Freeze the current desktop

- Tag the current stable state.
    
- Create a dedicated rebuild branch.
    
- Add screenshots and a functional inventory.
    
- Record startup time, idle memory, process count and known breakages.
    
- Preserve Wayle as the fallback shell.
    

## Phase 1 — Clean the foundation

- Introduce the new repository structure.
    
- Eliminate absolute home paths.
    
- Move process lifecycle to systemd user units.
    
- Separate required and optional packages.
    
- Define configuration and IPC schemas.
    
- Consolidate logs under `$XDG_STATE_HOME/noxflow`.
    

No visual redesign yet.

## Phase 2 — Build `noxd`

- Implement settings and profile loading.
    
- Add Hyprland, audio, network, Bluetooth, battery and media providers.
    
- Add event subscriptions.
    
- Expose IPC and `noxctl`.
    
- Replace the fastest polling scripts first.
    

Acceptance condition: the daemon can provide all bar data without periodic shell pipelines.

## Phase 3 — Build the QML foundation

- Typography
    
- Icons
    
- Semantic colours
    
- Spacing
    
- Cards
    
- Buttons
    
- Menus
    
- Tooltips
    
- Motion primitives
    
- Focus and keyboard navigation
    
- Reduced-motion support
    
- Multi-monitor placement
    

Acceptance condition: every surface can use the same components without custom styling.

## Phase 4 — Replace the daily shell

Build in this order:

1. OSD and Nox Island
    
2. Minimal bar
    
3. Launcher
    
4. Control centre
    
5. Notification centre
    
6. Clipboard
    

Wayle remains one command away until these are stable.

## Phase 5 — Add the differentiating features

- Workspace overview
    
- Radial shortcut wheel
    
- Dashboard
    
- Capture/OCR/Lens workflow
    
- Calendar
    
- Theme profiles
    
- Project/workbench drawer
    
- Shell settings UI
    

## Phase 6 — Integrate AI carefully

- On-demand Khoj search
    
- Local model status
    
- Ask-from-clipboard
    
- Explain selected text
    
- Search project documentation
    
- RTK-backed compressed agent commands
    
- Completion notifications through Nox Island
    

AI failure must never affect login, the bar, launcher or ordinary settings.

## Phase 7 — Remove the old stack

Only after parity:

- Delete Wayle configuration
    
- Delete replaced Rofi/Python interfaces
    
- Remove redundant packages
    
- Simplify startup
    
- Update bootstrap and doctor checks
    
- Regenerate documentation
    
- Measure startup and idle resource changes
    

# Recommended final combination

The strongest result is not a clone of any one repository.

It should be:

- **DankMaterialShell’s architecture**
    
- **Caelestia’s motion and surface transitions**
    
- **end-4’s feature ambition**
    
- **Monochrome OS’s restraint and radial interaction**
    
- **Tide Island’s contextual live activities**
    
- **QuickSnip’s unified capture workflow**
    
- **Waylandar’s calendar surface**
    
- **HyDE’s theme packaging**
    
- **Your existing project, AI and workstation automation**
    

That would produce a desktop that looks intentional and remains maintainable.

## Decisions for the implementation

My recommended defaults are marked in bold:

## Direction locked

### 1. Visual style — **Material-heavy**

The desktop will use a strong Material 3-inspired language:

- Large rounded surfaces
- Layered containers
- Morphing panels
- Expressive but controlled animations
- Clear elevation and hierarchy
- Oversized dashboard components
- Rich quick settings
- Strong active-state feedback
- Wallpaper-driven colour
- Consistent touch-friendly targets, even on desktop

It should feel closer to a modern operating system shell than a conventional Linux rice.

This does **not** mean copying Android. We will adapt Material principles for mouse, keyboard and large displays.

---

### 2. Architecture — **Quickshell + Rust `noxd`**

The final stack:

```
Hyprland
   │
   ├── Quickshell / QML
   │     ├── Bar
   │     ├── Nox Island
   │     ├── Launcher
   │     ├── Workspace overview
   │     ├── Control centre
   │     ├── Notifications
   │     ├── Dashboard
   │     ├── Clipboard
   │     └── Capture centre
   │
   ├── noxd
   │     ├── Hyprland events
   │     ├── Audio
   │     ├── Network
   │     ├── Bluetooth
   │     ├── Battery
   │     ├── Media
   │     ├── Calendar
   │     ├── Clipboard
   │     ├── Git/project state
   │     └── Local AI state
   │
   └── noxctl
         ├── Shell commands
         ├── Settings
         ├── Profiles
         ├── Diagnostics
         └── Automation
```

The shell will consume structured state from `noxd`. It will not repeatedly execute shell pipelines to determine basic system state.

---

### 3. Migration — **Wayle remains as fallback**

Wayle stays installed during development.

The shell switcher should support:

```
noxctl shell use noxflow
noxctl shell use wayle
noxctl shell restart
noxctl shell safe-mode
```

A login failure must automatically fall back to Wayle or a minimal emergency bar.

Nothing old gets removed until its replacement passes feature-parity checks.

---

### 4. Overview — **Hyprland plugin with QML fallback**

Primary experience:

- Live workspace thumbnails
- Smooth scroll navigation
- Drag windows between workspaces
- Keyboard-first window selection
- Named workspaces
- Project/workspace indicators
- Scratchpad and sidecar visibility

Preferred implementation:

```
Compatible plugin available
        ↓
Use native Hyprland overview integration

Plugin missing or ABI broken
        ↓
Use Quickshell overview fallback
```

This prevents a Hyprland update from breaking the core desktop workflow.

---

### 5. AI — **On-demand**

AI will not occupy permanent desktop space.

It will appear through:

- Universal launcher commands
- Clipboard actions
- Capture/OCR results
- Dashboard status
- Project workspace drawer
- Context menus
- Nox Island completion notifications

Example actions:

```
Explain clipboard
Rewrite selected text
Ask about current repository
Summarise terminal error
Generate shell command
Search local documentation
Resume project context
Review Git changes
```

Local AI failure will not affect the shell, bar, launcher or login process.

---

## 6. Theme system — combined **6A + 6C**

The correct combination is:

> **Named Material profiles whose accent palettes are generated from the current wallpaper.**

Wallpaper colours should not directly control everything. That often creates unreadable or ugly themes.

Instead, each profile defines the visual rules, and the wallpaper provides controlled accent candidates.

### Profiles

#### Material Expressive

Default everyday profile.

- Strong wallpaper-derived primary colour
- Large rounded corners
- Moderate blur
- Expressive transitions
- Rich tonal surfaces
- Distinct containers
- Prominent active states

#### Material Focus

For development and concentrated work.

- More neutral surfaces
- Lower saturation
- Fewer animations
- Reduced transparency
- Smaller dashboard density
- Wallpaper colours limited to small accents

#### Material Ambient

For casual usage and media.

- Strong wallpaper integration
- More translucency
- Larger media surfaces
- Animated gradients
- Richer island and dashboard presentation

#### Material Performance

For gaming, external displays or battery pressure.

- No blur
- Minimal shadows
- Reduced motion
- Simplified bar
- Static background surfaces
- Lower shell refresh cost

#### Material OLED

Optional dark profile.

- Near-black foundation
- High-contrast text
- Wallpaper-derived accent
- Minimal raised surface brightness
- Suitable for dark environments

---

## Colour-generation behaviour

The wallpaper pipeline should:

1. Analyse the wallpaper.
2. Extract several candidate colours.
3. Reject extremely dark, bright or low-contrast candidates.
4. Generate Material-style tonal palettes.
5. Apply the selected profile’s saturation and contrast limits.
6. Generate configuration adapters.
7. Reload only affected applications.

Generated palette example:

```
[palette]
source = "/home/namik/Pictures/Wallpapers/current.png"
profile = "material-expressive"

primary = "#A9C7FF"
on_primary = "#002F64"
primary_container = "#1E477D"
on_primary_container = "#D5E3FF"

secondary = "#BBC7DB"
on_secondary = "#253141"
secondary_container = "#3B4858"
on_secondary_container = "#D7E3F8"

tertiary = "#D9BDE4"
surface = "#111318"
surface_container = "#1D2026"
surface_container_high = "#282A30"
outline = "#8D9199"
```

The generated theme will be consumed by:

- Quickshell
- Hyprland
- Hyprlock
- SDDM
- GTK 3
- GTK 4
- Qt/Kvantum
- Kitty
- Neovim
- Chrome
- Rofi fallback
- Notification fallback

---

# Final shell identity

The working name should remain:

# **NoxFlow Shell**

Primary surfaces:

|Surface|Purpose|
|---|---|
|**Nox Bar**|Minimal persistent navigation and status|
|**Nox Island**|Temporary activities and system feedback|
|**Nox Search**|Applications, windows, commands, files, projects and AI|
|**Nox Control**|System settings and hardware controls|
|**Nox Overview**|Workspaces and windows|
|**Nox Centre**|Notifications and agenda|
|**Nox Capture**|Screenshots, OCR, annotation, search and sharing|
|**Nox Board**|Full dashboard|
|**Nox Workbench**|Development project state and local AI|
|**Nox Settings**|Shell configuration and visual profiles|

---

# First implementation sprint

Do not begin by building the dashboard. Start by removing architectural disorder.

## Sprint 1 — Foundation

### Repository changes

```
shell/noxflow/
core/noxd/
cli/noxctl/
config/
theme/
systemd/user/
legacy/
```

### Initial work

1. Tag the current repository as the stable pre-rebuild state.
2. Create a `noxflow-shell` development branch.
3. Move current Wayle configuration under `legacy/wayle`.
4. Keep symlinks pointing to the existing working locations.
5. Introduce `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME` and `$XDG_CACHE_HOME` consistently.
6. Remove hard-coded `/home/namik` paths.
7. Move startup daemons into systemd user services.
8. Define `noxd` IPC types.
9. Define shared theme tokens.
10. Create a minimal Quickshell process with one test surface.
11. Add automatic fallback to Wayle.
12. Record idle RAM, process count and startup timing before further work.

### First visible deliverable

The first visible version should contain only:

- Material top bar
- Workspace indicators
- Clock
- Network/audio/battery cluster
- Nox Island for volume and brightness
- Wallpaper-derived Material palette
- Wayle fallback command

Do not add the launcher, dashboard, calendar or AI before this foundation is reliable.

---

# Hard rules for the rebuild

- No absolute user paths.
- No shell polling faster than necessary.
- No duplicate UI for the same action.
- No permanent telemetry clutter in the top bar.
- No AI dependency in the critical desktop path.
- No removing Wayle before parity.
- No copied rice installed wholesale.
- No individual component inventing its own colours or spacing.
- No daemon started through a giant `startup.sh` when systemd can own it.
- Every major surface must work with keyboard navigation.
- Every animation must respect reduced-motion mode.
- Every plugin-dependent feature needs a fallback.
- Every generated theme must pass contrast checks.