# 03 — Design Contract

**Date:** 2026-07-31
**Branch:** `codex/unified-shell-redesign-20260728`

This contract fixes the shell's interaction model so M6 (state machine) and M7
(morph engine) implement a single, coherent design. No component may define
arbitrary animation durations once motion tokens exist.

---

## 1. Surface hierarchy

```
base desktop (windows, wallpaper)
  ├─ TopBar (persistent, per-screen, layer-shell)
  │    ├─ workspaces (left)
  │    ├─ central clock island (origin for morphs)
  │    ├─ active-window label
  │    ├─ media pill
  │    └─ status cluster (network, bluetooth, volume, battery, notifications)
  ├─ CentralIsland (per-screen, below bar; OSD + morph origin)
  │    └─ compact state: clock/activity pill
  │    └─ expanded states: calendar, media, notifications, control sections
  ├─ SidePanels (temporary)
  │    ├─ right: control centre, notification centre, calendar, media
  │    └─ left: Quick Share / transfer activity
  ├─ Overlays (full-screen, exclusive)
  │    ├─ Launcher (SUPER+SPACE)
  │    ├─ Dashboard
  │    ├─ Settings
  │    ├─ Capture
  │    └─ ScrollOverview (plugin — external)
  └─ OSD (NoxIsland — transient feedback, no user interaction)
```

## 2. Shell states (semantic, not integers)

```
idle            → rest (bar + compact island only)
media           → island expanded to media player
calendar        → island expanded to calendar
control-center  → island expanded to control centre (sections: network,
                  bluetooth, volume, brightness, power, battery)
notifications   → island expanded to notification centre
system-monitor  → island expanded to system stats
wallpaper       → island expanded to wallpaper/theme picker
clipboard       → island expanded to clipboard history
quick-share     → LEFT side panel (persistent workflow)
launcher        → full-screen overlay
session-menu    → full-screen overlay (power menu)
```

## 3. State transition rules

### 3.1 Which states can replace each other

| From \ To | media | calendar | cc | notif | system | wallpaper | clipboard | share | launcher |
|---|---|---|---|---|---|---|---|---|---|
| idle | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| media | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| calendar | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| cc | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| notif | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ |
| system | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ |
| wallpaper | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| clipboard | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| share | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| launcher | ✗* | ✗* | ✗* | ✗* | ✗* | ✗* | ✗* | ✗* | — |

\* Launcher is exclusive: opening it closes any island/panel state first.

### 3.2 Coexistence

- **Island states are mutually exclusive** (one expanded island per screen).
- **Quick Share (left panel) may coexist** with a right-side island state
  (transfer activity stays visible while control centre is open).
- **OSD (NoxIsland) is always transient** and independent of island/panel
  states; it never steals focus.
- **Overlays** (launcher/dashboard/settings/capture) close all island/panel
  states when opened.

### 3.3 Focus policy

| State | Keyboard focus | Click-through | Escape |
|---|---|---|---|
| bar | tab-cycle | n/a (layer) | n/a |
| compact island | no | n/a | n/a |
| expanded island | yes (when interactive) | no (surface bounds) | close → idle |
| quick-share panel | yes | no | close → idle |
| launcher/dashboard/settings/capture | yes | no | close |
| OSD | no | yes | n/a |

### 3.4 Escape chain

1. Topmost overlay (launcher > dashboard > settings > capture)
2. Expanded island / side panel (closes → idle)
3. Nothing → Escape consumed by compositor/window

### 3.5 Monitor behavior

- Island/panels are per-screen (the screen that owns the trigger chip).
- Overlays are per-screen too (open on active screen).
- If the trigger screen disconnects mid-morph: close the surface immediately,
  restore defaults.

### 3.6 Interruption

- A new `requestedState` during any transition: retarget the in-flight
  animation to the new state. The morph engine must never "queue" states —
  it retargets.
- Rapid toggle (open → close → open): each request retargets; the engine
  settles to the final requested state.

## 4. Design tokens

Already centralized in `theme/Tokens.qml` (M3 design tokens) and
`config/ShellConfig.qml`. No new token system. Key values:

| Token | Value |
|---|---|
| bar height | 40 (`heightToolbar`) |
| bar margins | 8 (`barMargin`) |
| corner radius (panels) | `radiusXl` 24 |
| corner radius (pill) | `radiusPill` 999 |
| surface color | `surfaceSurfaceContainerHigh` |
| border | `outlineDefault` 1px |
| blur | disabled by default (`enableBlur: false`), max `blurSubtle` 8 |
| shadow | from Hyprland `decoration:shadow` |
| accent | `tonalPrimary` |
| icon size | `iconSm` 20 / `iconMd` 24 / `iconLg` 32 |

## 5. Motion tokens

Extend `config/Motion.qml` with morph-specific tokens (M6/M7 consume these):

| Token | Value | Notes |
|---|---|---|
| `hover` | 140 × factor | existing |
| `toggle` | 150–180 | selection toggles |
| `morphCompact` | 220–280 | island compact→expanded |
| `morphLarge` | 300–380 | panel-size morph |
| `contentExit` | 115 × factor | existing |
| `contentEnter` | 150 × factor | existing |
| `radiusInterpolate` | 220 | corner radius morph |
| `settle` | 60–100 | settle after geometry |

Easing: `OutCubic`/`OutQuart` for large geometry. **No `OutBack` overshoot on
panel dimensions.** Reduced-motion mode: skip all geometry animation, jump to
target.

## 6. Morph phases (M7 implements)

### Opening
1. `preparing` — mount destination content invisibly; capture source geometry
   from `MorphRegistry` chip.
2. `expanding` — grow layer-surface window immediately to target bounds (avoid
   clipping); animate visual frame geometry + radius.
3. `crossfade` — at ~40% of geometry transition, fade compact content out and
   expanded content in.
4. `settled` — geometry stable; enable input; set `interactive`.

### Closing
1. Disable interaction.
2. Fade expanded content out (contentExit).
3. Animate frame toward compact island geometry; **retain layer-window height**
   until the visual frame collapses.
4. Restore compact content.
5. Shrink actual layer surface.
6. Unmount expanded content (delayed).

### Interruption
Any new `requestedState` retargets the in-flight animation; never queue.

## 7. Quick Share panel (M12)

- Left-side, anchored to left edge; share state model:
  `discovered → offered → awaiting-acceptance → connecting → transferring →
  verifying → completed | declined | cancelled | failed`
- Coexists with right-side island states.
- Compact transfer status may appear in the central island while active.
