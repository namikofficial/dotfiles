# 02 — Reference Analysis

**Date:** 2026-07-31
**Branch:** `codex/unified-shell-redesign-20260728`
**Supersedes:** the "Do NOT adopt" note for hyprland-scroll-overview in
`REFERENCES.md` (user decision 2026-07-31: adopt the plugin, delete the QML
Overview).

---

## 1. hyprland-scroll-overview (adopted)

**Source:** https://github.com/yayuuu/hyprland-scroll-overview
**Decision:** ADOPT as the primary window/workspace navigator. Delete the QML
`Overview.qml`. Rebuild after every Hyprland upgrade (ABI-breaking).

### Installation (from upstream README, verified 2026-07-31)

```bash
hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git
# Git build of Hyprland? use: hyprpm add <repo> origin/new-release
hyprpm update          # build + fetch deps
hyprpm enable scrolloverview
```

The repo's startup.sh notes a known HyprPM header-refresh issue on Hyprland
0.54.1 (`hyprpm` fails with "You need to run make all first"). If `hyprpm add`
fails, fall back to source build:

```bash
git clone https://github.com/yayuuu/hyprland-scroll-overview.git /tmp/scroll-overview
cmake -S /tmp/scroll-overview -B /tmp/scroll-overview/build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/scroll-overview/build -j
hyprctl plugin load /tmp/scroll-overview/build/libscrolloverview.so   # verify name from build output
```

Persistence: add `exec-once = hyprctl plugin load ...` or enable via HyprPM.

### Lua configuration (this repo uses hyprland.lua)

```lua
hl.config({
  plugin = {
    scrolloverview = {
      gesture_distance = 300,
      scale = 0.56,
      workspace_gap = 72,
      layout = "horizontal",
      wallpaper = 0,
      blur = false,
      input = {
        scroll_event_delay = 140,
        touchpad_scroll_factor = 1.0,
        scrolling_mode = 0,
        drag_mode = 0,
        drag_threshold = 10,
      },
      shadow = {
        enabled = true,
        range = 24,
        render_power = 3,
        color = 0x66000000, -- integer color in Lua (rgba() NOT accepted)
      },
    },
  },
})
```

Lua note from upstream: `shadow.color` must be an **integer color value or a
gradient**, not `rgba(...)`.

### Dispatchers (authoritative)

| Dispatcher | Options |
|---|---|
| `scrolloverview:overview` | `toggle [monitor\|all]`, `select`, `close [monitor\|all]`, `off`, `disable`, `open`, `on`, `enable` |
| `scrolloverview:navigate` | `left`, `right`, `up`, `down` |
| `scrolloverview:window` | `select`, `close` |

Lua equivalents: `hl.plugin.scrolloverview.overview("toggle")`,
`hl.plugin.scrolloverview.navigate("left")`,
`hl.plugin.scrolloverview.window("close")`.

### Bindings (Lua form for this repo)

```lua
-- Toggle overview
bind(mainMod .. " + Tab", function()
  hl.config({ plugin = { scrolloverview = { layout = "horizontal" } } })
  hl.plugin.scrolloverview.overview("toggle")
end)

-- Gesture
hl.plugin.scrolloverview.gesture({ fingers = 3, direction = "vertical" })

-- Optional submap for keyboard-complete navigation
hl.define_submap("scrolloverview", function()
  hl.bind("left",   hl.plugin.scrolloverview.navigate("left"))
  hl.bind("right",  hl.plugin.scrolloverview.navigate("right"))
  hl.bind("up",     hl.plugin.scrolloverview.navigate("up"))
  hl.bind("down",   hl.plugin.scrolloverview.navigate("down"))
  hl.bind("h",      hl.plugin.scrolloverview.navigate("left"))
  hl.bind("l",      hl.plugin.scrolloverview.navigate("right"))
  hl.bind("k",      hl.plugin.scrolloverview.navigate("up"))
  hl.bind("j",      hl.plugin.scrolloverview.navigate("down"))
  hl.bind("return", hl.plugin.scrolloverview.overview("select"))
  hl.bind("space",  hl.plugin.scrolloverview.overview("select"))
  hl.bind("escape", hl.plugin.scrolloverview.overview("off"))
  hl.bind("mouse:272", function()
    hl.plugin.scrolloverview.overview("select")
    hl.plugin.scrolloverview.window("select")
    hl.plugin.scrolloverview.overview("off")
  end, { mouse = true })
  hl.bind("mouse:274", hl.plugin.scrolloverview.window("close"), { mouse = true })
end)
```

Note: when a `scrolloverview` submap is defined, the built-in keyboard
navigation is replaced. Universal binds (e.g. `SUPER+1..0` workspace switch)
can be preserved with `submap_universal = true`.

### Gesture syntax (Hyprlang / Lua)

```
scrolloverview-gesture = 3, up, overview
hl.plugin.scrolloverview.gesture({ fingers = 3, direction = "vertical" })
```

### Upgrade/rebuild implications

- Hyprland upgrades change the plugin ABI. After every `hyprctl version` bump:
  `hyprpm update` then `hyprpm enable scrolloverview` (or rebuild from source).
- The repo already tracks this pattern in `docs/HYPRLAND_POST_UPGRADE.md`
  (hyprexpo rebuild notes). Add a scroll-overview section there.
- A rebuild helper script will be added in M10 (`hypr/scripts/scrolloverview-rebuild.sh`).

---

## 2. Tide Island (feature coverage reference)

**Source:** https://github.com/enhaoswen/Tide-island
**Decision:** ADOPT for feature coverage, dynamic-island behavior, panel
styling, and lifecycle engineering.

### Concepts to port (verified against the repo's working implementation)

| Tide concept | Port target in this repo |
|---|---|
| Root `PanelWindow` managing the visible input region | `core/MorphSurface.qml` (rewrite in M7) |
| Dynamic island frame with width/height state | `NoxIsland.qml` → becomes central island |
| State machine with `mounted` vs `visible` vs `interactive` | `core/PanelController.qml` (rewrite in M6) |
| Retained layer-surface height during collapse | `MorphSurface` close sequence (M7) |
| Input mask / click-through outside actual surface | `MorphSurface` input Region (M7) |
| Loading phases and keyboard-focus policy | `SurfaceLifecycle.qml` extension |
| Auto-hide with interaction extension | `NoxIsland` hideTimer + hover extension |
| Control centre / notification centre / media panel | existing panels in `surfaces/` |
| Wallpaper picker with immediate previews | M13 (new) |
| System monitor with bounded history | `SystemModel.qml` extension |
| MPRIS media | `MediaModel.qml` (exists) |
| Theme tokens / configuration | `theme/Tokens.qml` + `config/ShellConfig.qml` |

### Engineering notes from the Tide implementation (applies to M7)

- The main window manages the **visible input region** — when the panel
  morphs, the layer-surface window must stay large enough to avoid clipping
  while the visual frame collapses.
- Separate **mounted / visible / interactive** states prevent content from
  disappearing halfway through a collapse.
- Focus policy: keyboard focus is only granted when a surface is
  interactive, never during a transition.

---

## 3. Ilya Miro (spatial transformation language)

**Source:** https://github.com/ilyamiro/nixos-configuration
**Decision:** ADOPT the QML animation/choreography concepts only. Do NOT port
the NixOS deployment structure.

### Concepts to port

| Ilya Miro concept | Port target |
|---|---|
| Popup opening sequence (mount → measure → expand → fade-in) | `MorphSurface` open phases (M7) |
| Popup closing sequence (fade-out → collapse → unmount) | `MorphSurface` close phases (M7) |
| Width/height/radius interpolation | `MorphSurface` geometry animation |
| Translation + opacity choreography for content | content crossfade at ~40% of geometry transition |
| Delayed content mount/unmount | `Loader.active` timing (M7) |
| Keyboard focus + Escape handling | `SurfaceLifecycle` + `SurfaceCoordinator` |
| Shared visual origin (chip → panel) | `MorphRegistry` chip geometry |

### Motion language (recommended, matches existing `config/Motion.qml`)

- Hover: 90–130 ms
- Toggle selection: 150–180 ms
- Compact island expansion: 220–280 ms
- Large panel expansion: 300–380 ms
- Content exit: 90–130 ms
- Content enter: 140–190 ms
- **No overshoot on large panel dimensions** (OutCubic/OutQuart only)
- Slight overshoot acceptable for tiny indicators/buttons only

---

## 4. LocalSend (Quick Share backend)

**Source:** https://github.com/localsend/localsend (and `localsend-bin` AUR)
**Decision:** ADOPT as the transfer backend for the Quick Share panel.

### Detection (already in repo)

- `setup/aur-packages.txt:7` → `localsend-bin|localsend-appimage`
- `hypr/scripts/lib/quick-actions.sh:126` → `flatpak run org.localsend.localsend_app`

### Integration plan (M12)

1. Detect installed form: `command -v localsend` (AUR binary) vs flatpak.
2. Ensure autostart (systemd user service or startup.sh `run_once`) so the
   daemon is discoverable at login.
3. Verify CLI surface of the installed version before wiring
   (`localsend send`, `localsend receive`, `localsend pair`, `localsend list`).
4. `TransferService.qml` wraps the CLI via `Quickshell.Io.Process`:
   - `discovered` → device list
   - `offered` / `awaiting-acceptance` → incoming request events
   - `transferring` → progress from CLI output
   - `completed` → file-exists check + notification
5. Left-side Quick Share panel with device list, file picker, progress cards,
   history.

### Syncthing (companion, already working)

- `hypr/scripts/syncthing-control.sh` — UI + config
- Sync folders remain usable as transfer destinations via the companion
  integration; the panel's primary backend is LocalSend.

---

## 5. Superseded decisions

| Item | Old decision | New decision |
|---|---|---|
| hyprland-scroll-overview | Do NOT adopt (ABI) | ADOPT (user decision), delete QML Overview |
| REFERENCES.md entry | "Do NOT adopt" | update to ADOPT + rebuild burden note |
