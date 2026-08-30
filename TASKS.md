# NoxFlow Refactor — Task Board

**Branch:** `inspired-rewrite`
**Status:** ✅ All phases complete. 0 errors, 0 non-benign warnings. See completed sessions below.

---

## Phase 0 — Fix What Was Broken (2026-07-28) ✅

| Task | Reality |
|------|---------|
| OCR: grim → tesseract pipe via libquickshell Process with stdout capture, no shell redirects | **REAL** — `Capture.qml:234-252` uses `Process { command: ["sh", "-c", "grim…-| tesseract"] }` with onExited + SplitParser |
| Clipboard persistence: FileView + onLoaded/setText instead of shell-echo injection | **REAL** — `ClipboardModel.qml:81-109` uses `FileView` with JSON serialization |
| Bar.qml 6× `parent is not defined` + undefined bool | **FIXED** — all right indicators wrapped in FocusScope chips with `implicitWidth/Height` |
| Tooltip.qml:14 undefined QObject\* + deprecation warnings | **FIXED** — `anchor.window`/`anchor.item`/`anchor.rect` API, ternary guards |
| Overview + RadialWheel Keys warnings | **FIXED** — Keys moved to inner `Item { focus: true }` |
| `transformOrigin: Item.X` → Qt.X | **REMOVED** — QQuickItem enum mismatch; default is fine |
| `width/height` on WlrLayershell surfaces | **FIXED** → `implicitWidth/Height` |
| `shellRoot` missing `id:` in shell.qml | **FIXED** — added `id: shellRoot` |
| AI endpoint hardcoded | **FIXED** — `Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/…"` |
| NoxIsland unvalidated state string | **FIXED** — `onIslandStateChanged` guard with `validStates` array |
| `REFERENCES.md` | **CREATED** — pinned commit entries for all reference repos |

**Exit gate:** zero runtime errors/warnings (except benign `FileView: file does not exist` on first run).

## Feature Reality Matrix (current — everything is REAL now)

| Feature | Status | Notes |
|---|---|---|
| Capture with dual-polarity OCR + WordOverlay + Lens upload | **REAL** | `Capture.qml` — TSV-based per-word extraction, smart analysis (URL/code/AI/search detection), Lens via curl, env-configurable settings |
| Calendar with Google Calendar sync | **REAL** | `CalendarModel.qml` — FileView cache reader + `sync.py` (full gcalcli backend), background sync timer (5 min), expandable event cards with color accent bars |
| NoxIsland priority queue + auto-hide | **REAL** | `NoxIsland.qml` — priority map (notification=10→idle=0), concat+reassign queue, edge-gesture reveal, hover-expand, recording 30s auto-hide |
| Rivendell falling-knight notification physics | **REAL** | `NotificationItem.qml` — FrameAnimation spring-damper (spring=1.0, damping=0.1, gravity=3000), 4-state fling-to-dismiss |
| Weather model + Bar chip + Dashboard forecast | **REAL** | `WeatherModel.qml` — wttr.in fetch, FileView cache, 3-day forecast tiles in Dashboard |
| Clipboard history (safe persistence) | **REAL** | `ClipboardModel.qml` — FileView JSON, Process stdin write |
| Morphing animations registry + scaffold | **REAL** | `MorphRegistry.qml` + `MorphingSurface.qml` — 4 Bar chips registered, NotificationCentre receives `morphRegistry` |
| InstanceTracker (clean per-screen management) | **REAL** | `InstanceTracker.qml` — replaces 6× copy-pasted push/splice patterns |
| Overview horizontal kinetic scroll | **REAL** | `Overview.qml` — Flickable + WheelHandler + smooth 350ms OutCubic, scroll-into-view on keyboard nav |
| All close animations pre-declared | **REAL** | 0 `Qt.createQmlObject` calls remain across 12 surfaces |

## Completed Build Sessions

### Build Session 1 (Phase 0 — structural fixes)
- OCR Process pipe (grim|tesseract stdin/stdout)
- Clipboard persistence (FileView JSON)
- Bar.wqml FocusScope chips (8 indicators wrapped)
- Tooltip anchor API migration
- Overview + RadialWheel Keys fix
- shellRoot id, width/implicitWidth, AI endpoint, NoxIsland guard
- REFERENCES.md, TASKS.md reality column, PLAN.md

### Build Session 2 (Phases A/B/E — animations + queue)
- Rivendell falling-knight physics (FrameAnimation spring-damper)
- Tide-island priority queue (priority map + concat queue)
- Chip morph registry + scaffold
- Weather (wttr.in, FileView, forecast)
- Pre-declared close animations (Capture, Calendar, NotificationCentre)

### Build Session 3 (Phases C/D/G — features)
- QuickSnip unified capture (TSV parser, WordOverlay, smart analysis, Lens curl)
- Waylandar calendar sync (Python backend, multi-account, FileView reader)
- Overview horizontal kinetic scroll (Flickable + wheel + smooth)
- Dashboard forecast tiles + calendar sync trigger
- InstanceTracker.qml (replace 6x push/splice)
- 3 remaining Qt.createQmlObject → pre-declared SequentialAnimation
- All 12 surfaces now use pre-declared close animations

## Compilation Fixes (runtime enabling)

All errors fixed to get the shell loading:
- `PanelWindow` does not support `anchors.fill` — use 4 boolean anchors (top/bottom/left/right) ✅
- `PanelWindow` does not support `opacity` — removed from Capture, fixed `Behavior on opacity` ✅
- `PanelWindow` does not support `anchors.horizontalCenter` — removed from NoxIsland ✅
- `NumberAnimation` does not support `enabled` property — removed everywhere ✅
- `Behavior` does not support `enabled` property — removed everywhere ✅
- `RowLayout`/`ColumnLayout` do not support `padding` — removed ✅
- `TextInput` does not support `placeholderText` — rendered as overlay `Text` ✅
- `TextInput` does not support `cursorShape` — removed ✅
- `TextInput` does not support `anchors { ... }` group syntax with semicolons — converted to dotted properties ✅
- Duplicate `placeholderText` assignment in Launcher.qml — removed duplicate ✅
- Duplicate `signal textChanged` (conflicted with auto-generated property change signal) — removed explicit signal ✅

---

## Architecture

```
shell/noxflow/
├── shell.qml                    # Entry point — wires all 10+ surfaces
├── NoxIsland.qml                # 10-state FSM island
├── Bar.qml                      # Top bar with status widgets
├── NotificationModel.qml        # Local notification store + DND + history
├── CalendarModel.qml            # Calendar state + events
├── ClipboardModel.qml           # Clipboard history store
├── NoxdClient.qml               # IPC client for noxd daemon
├── Protocol.js                  # IPC protocol helpers
├── ModelUtils.js                # Shared model utilities
├── AudioModel.qml / BrightnessModel.qml / etc.  # Provider models
├── theme/
│   ├── Tokens.qml               # M3 design tokens (writable)
│   ├── ThemeProfiles.js         # 5 colour palette definitions
│   ├── ThemeProfiles.qml        # QML wrapper for JS module
│   └── qmldir                   # Module exports
├── components/                  # Shared UI primitives
│   ├── Elevation.qml / StateLayer.qml / MaterialIcon.qml
│   ├── TextField.qml / Divider.qml / Surface.qml
│   ├── Card.qml / Toggle.qml / Slider.qml / IconButton.qml
│   ├── TextButton.qml / StatusChip.qml / LoadingIndicator.qml
│   ├── FocusRing.qml / Tooltip.qml / PopupContainer.qml
│   └── ControlTile.qml / NotificationItem.qml
├── surfaces/
│   ├── controlcenter/ControlCentre.qml   # 4-tab control panel (debounced sliders, DND, battery mode)
│   ├── notifications/NotificationCentre.qml # Morphing notif panel
│   ├── notifications/NotificationCentre.qml # Morphing notif panel
│   ├── island/ (NoxIsland lives at root)
│   ├── launcher/Launcher.qml               # 6-mode universal launcher
│   ├── overview/Overview.qml               # Workspace grid
│   ├── capture/Capture.qml                 # Region selector + OCR
│   ├── radial-menu/RadialWheel.qml         # Canvas shortcut wheel
│   ├── calendar/CalendarWidget.qml         # Month grid + agenda
│   ├── dashboard/Dashboard.qml             # Full-screen hub
│   └── settings/SettingsPanel.qml          # Theme + appearance controls
└── Gallery.qml                   # Component/surface showcase
```

## Keybinds (Hyprland)

| Surface | Key | Description |
|---------|-----|-------------|
| Launcher | `SUPER + Space` / `SUPER + SHIFT + Space` | 6-mode launcher (Apps/Windows/Commands/Calc/Ask AI/Clipboard) |
| Workspace Overview | `SUPER + W` / `SUPER + Y` / `SUPER + CTRL + Space` / `SUPER + SHIFT + Tab` | Full-screen grid |
| Notifications | `SUPER + N` | Notification centre panel |
| Capture | `SUPER + SHIFT + S` | Region screenshot + OCR/Lens toolbar |
| Settings | `SUPER + ,` | Theme profiles, density, motion, radius |
| Dashboard | `SUPER + D` | Full-screen command hub |
| Calendar | `SUPER + SHIFT + C` | Month grid + agenda |
| Control Centre | `SUPER + SHIFT + B` | 4-tab audio/network/display/power panel |

Use `noxctl <surface>` from terminal to trigger any surface directly.

## IPC Wiring

All surfaces connect through `NoxdClient.qml` (Unix socket → noxd daemon):
- `runAction(action)` — typed actions (audio, brightness, power, network, etc.)
- `setSetting(key, value)` — persist settings changes through the daemon
- Toggle functions in `shell.qml` exposed to `IpcHandler` target `noxctl` for keybind control
- 8 toggle + open/close IPC handlers registered; invoke via `quickshell ipc -p ~/.config/noxflow/shell call noxctl toggleLauncher`
