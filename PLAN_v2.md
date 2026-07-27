# NoxFlow Refactor Plan v2 — One Surface, Infinite Morphs

**Branch:** `inspired-rewrite` · **Date:** 2026-07-28 · **Supersedes:** `PLAN.md`
**Research basis:** Deep-study of 15 reference repos + 6 Reddit posts + 3 review agents

---

## 0. Immediate Cleanup (do this first, 5 minutes)

After this session (plan mode), the first exec step:

```bash
systemctl --user stop wayle.service waybar.service 2>/dev/null
systemctl --user disable wayle.service waybar.service 2>/dev/null
systemctl --user restart noxflow-shell.service
```

Wayle is **still running** (`systemctl --user is-active wayle.service` → `active`). Waybar is inactive. The dual-shell is the most visible problem. Same process as the previous session — stop + disable wayle.

---

## 1. Big Picture: The Unified Vision

All the reference repos you love share a **single pattern**: one coherent surface that changes shape, never a collage of widgets.

| What you cited | The core pattern they share |
|---|---|
| **ilyamiro** navbar + morphing | Chip → panel geometry morphing, centered clock, panels animate from chip position |
| **Caelestia** shell | SDF blob-based panel morphing, all surfaces are one continuous shape |
| **end-4** dots | Usability-first, Material design, screen translation, AI integration |
| **end4-pC** | Sidebar, widgets, notification bar, shell config variants |
| **Tide Island** | Contextual island with priority queue + auto-hide state machine |
| **Rivendell** | Physics-based notification animations (FrameAnimation spring-damper) |
| **Waylandar** | Multi-account Google Calendar sync, expandable cards, undo toast |
| **QuickSnip** | Dual-polarity Tesseract OCR, word overlay, smart actions, Lens upload |
| **Scroll-overview** | **QML-only approach** — NOT the hyprlang plugin (ABI-breaking). Smooth kinetic scroll in QML Flickable. |

The plan builds these in a **layered, non-destructive** order — each phase adds one system, never breaks the previous.

---

## 2. Phase Map (updated from PLAN.md)

### Phase 0 — ✅ DONE (Fix what was broken)
OCR pipeline fixed, Clipboard safe, Bar warnings gone, Tooltip API clean, etc.

### Phase A — Stop dual-shell + Rivendell Notifications (3–4 days)
**(Move this before everything — most visible UX gap)**

| Step | What | Reference |
|---|---|---|
| A.0 | `systemctl --user stop/disable wayle.service` | — |
| A.1 | **Notification physics engine** — port Rivendell's `FrameAnimation` spring-damper into `NotificationItem.qml`. Custom Verlet-like per-frame spring: `dampingVelocity(currentVelocity, delta)` with spring=1.0, damping=0.1. Initial pop-in from 200px offset + 45° rotation → springs to (0,0,0°). Fling-to-dismiss: add gravity (3000 × frameTime to velocityY), knight sprite follows with velocityX × 0.2 rotation. | `rivendell/Notif.qml` |
| A.2 | **Notification Display** — adapt Rivendell's `Display.qml` (trumpet-top banner, parchment body) into existing `NotificationItem.qml`. Map hardcoded hex colors to `Theme.Tokens`. | `rivendell/Display.qml` |
| A.3 | **Notification sound effects** — `play` on arrival (trumpet) and fling (wilhelm scream). Optional `sox` dependency. | `rivendell/Notif.qml` |
| A.4 | **Auto-dim on hover** — `ListView` displaced/move/remove transitions (200ms OutCubic), lifetime 5000ms extended by hover. | `rivendell/Overlay.qml` |

**Files to create/modify:**
- `shell/noxflow/components/NotificationItem.qml` → rewrite with FrameAnimation physics
- `shell/noxflow/surfaces/notifications/NotificationCentre.qml` → add spring transition physics
- Optional: `assets/wilhelm-scream.ogg`, `assets/trumpet.wav`

**Dependencies:** `sox` (play command). Already have Quickshell.

---

### Phase B — NoxIsland → Tide-Island Parity (8–10 hours)

From research: your `NoxIsland.qml` (403 lines) already has 10 states, media/timer/recording support, and auto-hide timers. What's missing vs Tide's `DynamicIslandWindow.qml` (113KB):

| Missing | Implementation |
|---|---|
| **Priority queue** | Transient events (volume, brightness) interrupt → auto-restore to resting state. Add `stateQueue: []` + `restingState: string` |
| **Edge-gesture reveal** | Top-edge strip `topGestureInputX/Y/Width/Height` that reveals hidden island on mouse touch |
| **Hover-expand** | Capsule grows on hover; `hoverExpandEnabled`, `configuredHoverExpandAction` |
| **Timer completeness** | `timerActive`, `timerRemainingSeconds`, `timerBubbleWanted` with completion animation |
| **Recording integration** | `screenRecordingActive`, extended auto-hide delay (30s) |

**Files to modify:** `shell/noxflow/NoxIsland.qml`

---

### Phase C — QuickSnip Capture Pipeline (4–7 days)

Your `Capture.qml` (314 lines) has region selection, toolbar, and a just-fixed OCR pipe. QuickSnip adds:

| What | Implementation |
|---|---|
| **Dual-polarity OCR** | Run tesseract twice (normal + negated), score by confidence × word length + line bonus. Pick the better result. |
| **Word overlay** | Per-word highlight boxes with `minTouchSize: 28`, selection handles (top-pill + bottom-circle), smart toolbar positioning above/below selection. |
| **Smart text analysis** | URL detection, code detection (>3 code matches → "code"), dictionary (≤2 words), AI (≥15 words), search (fallback). |
| **Annotation layer** | Draw arrows, boxes, highlights on captured region before copy/save. |
| **Google Lens upload** | HTML form auto-submit to `lens.google.com/v3/upload` with base64 JPEG. Sidebar mode via `wlrctl` + `wtype` keyboard simulation. |
| **Settings** | `settings.json` with sections: Search, Selection, Translation, AI, Lens, Browser, OCR. |

**Files to create/modify:**
- `shell/noxflow/surfaces/capture/Capture.qml` → integrate dual-polarity OCR + smart analysis + annotation layer
- `shell/noxflow/surfaces/capture/WordOverlay.qml` → new, per-word highlight boxes
- `shell/noxflow/surfaces/capture/RegionSelector.qml` → new (or extract from Capture.qml), spring-animated selection
- `shell/noxflow/surfaces/capture/QuickSnipSettings.qml` → new, settings reader

**Dependencies:** `imagemagick`, `tesseract`, `wl-clipboard`, `wlrctl`, `wtype`

---

### Phase D — Waylandar Calendar Sync (5–10 days)

Your `CalendarModel.qml` (90 lines) has a stub `syncGCal()`. Waylandar has full multi-account sync:

| What | Implementation |
|---|---|
| **Backend sync** | Python script (`sync.py`) using `ThreadPoolExecutor` that fetches from Google OAuth, CalDAV (Nextcloud/iCloud), ICS feeds. Writes JSON cache files. |
| **Config** | `~/.config/waylandar/config.json` with OAuth tokens, calendar toggles, refresh intervals. |
| **Calendar grid polish** | Event dots on month grid, smooth opacity fades (0.3 → 1.0), expandable event cards with color accent bar + fade-in details. |
| **Undo toast** | 4-second countdown bar at bottom with "Undo" button after disabling a calendar. |
| **Dashboard integration** | Multi-pane overlay (sidebar + grid + agenda) when expanded. |
| **Reminders** | `notify-send` from backend when events are starting. Waylandar doesn't have reminders — add via `Timer` + notification. |

**Files to create/modify:**
- `shell/noxflow/CalendarModel.qml` → full rewrite with FileView cache reader + sync trigger
- `shell/noxflow/surfaces/calendar/CalendarWidget.qml` → event dots, expandable cards, opacity fades
- `shell/noxflow/surfaces/calendar/CalendarSidebar.qml` → calendar list + toggles
- `shell/noxflow/services/calendar-sync.sh` → Python sync script wrapper
- `external/waylandar-backend/` → Python backend (vendored or git submodule)

**Dependencies:** `python`, `google-auth-oauthlib`, `caldav`, `uv` (optional), `notify-send`

**⚠️ OAuth risk:** Add `waylandar-backend/config.json` and `*oauth*` to `.gitignore` before writing any code.

---

### Phase E — Chip-to-Panel Morphing + Navbar (4–6 hours)

This is the **#1 visual effect** you want — panels that morph from Bar chips (already scaffolded in Phase 0 with `chipRect()`, `clockGeometry`, `mediaChipGeometry`, etc.):

| What | Implementation |
|---|---|
| **MorphRegistry.qml** | Singleton tracking per-screen chip geometry snapshots. Snapshots destination at trigger time (not live — avoids mid-morph teleport on multi-monitor). |
| **MorphingSurface.qml** | Base component that wraps any surface. On open: reads `sourceRect` from registry, animates x/y/w/h/radius from source to target. On close: reverses. Non-blocking (input accepted from frame 0). |
| **Convert surfaces** in order: NotificationCentre → ControlCentre → CalendarWidget → SettingsPanel. Each gets a `morphFrom: string` property matching a chip id. Keep old entrance as fallback behind setting. |
| **Navbar refinement** | Use ilyamiro's centered-clock + three-section layout (already mostly there in Bar.qml). Ensure all chips have consistent `implicitHeight` and hover states. Add smooth `contentX` scroll for overflowing workspace chips. |

**Files to create/modify:**
- `shell/noxflow/MorphRegistry.qml` → new
- `shell/noxflow/components/MorphingSurface.qml` → new
- `shell/noxflow/Bar.qml` → already has `chipRect()` — add proper binding stability (snapshot vs live)
- Each PanelWindow surface → add morph wrapper

---

### Phase F — SDF Blob Panels (the Caelestia crown jewel, 12–16 hours)

Caelestia's blob system replaces separate `PanelWindow` surfaces with a **single full-screen container** per screen, where all panels are SDF-morphing overlays:

| What | Implementation |
|---|---|
| **BlobEffect.qml** | GLSL `ShaderEffect` implementing signed-distance field box with corner rounding. Single-input: position, size, radius → SDF value. |
| **BlobGroup.qml** | Merges multiple blob SDFs with configurable smoothFactor. When two panels are near, their corners "fill" — they merge into a continuous shape. |
| **BlobRect.qml** | Rectangle with spring-physics deformation matrix (`stiffness=200`, `damping=16`, `deformScale=0.0005`). Updates via `updatePhysics()` in `FrameAnimation`. |
| **Render panels via blobs** | Replace `PanelWindow` for CC/NC/Calendar/Settings/Dashboard. Each becomes a `BlobRect` registered in `BlobGroup`. The whole blob renders into one surface. |

This is **deferred until Phase E proves the chip-to-panel morph concept works** — the SDF approach is higher effort but produces caelestia-level beauty.

---

### Phase G — Overview Kinetic Scroll + Dashboard/Weather (3–5 days)

| What | Implementation | Reference |
|---|---|---|
| **Smooth kinetic scroll** | Replace static `Flow` in Overview with horizontal `Flickable` + scroll animation. Trackpad-aware via wheel events. **QML-only** — do NOT adopt the hyprland plugin (ABI breakage per Hyprland update). | scroll-overview concept |
| **Weather module** | `wttr.in` API fetch via `Process { command: ["curl", "wttr.in/...?format=j1"] }`, cache to FileView. Display in Dashboard + Bar chip. | quickdash |
| **Dashboard widget grid** | Add sections: Clock, Weather, Brightness, Volume, CPU/RAM, Media, Network, Bluetooth, Calendar events. Keyboard-driven navigation. | narexil-desktop |
| **Custom module loader** | Allow adding/removing dashboard sections via SettingsPanel. | — |

---

### Phase H — AI Integration + Screen Translation (end-4 style, configurable)

| What | Implementation |
|---|---|
| **AI is already scaffolded** | Launcher "Ask AI" mode hits `NOXFLOW_AI_ENDPOINT` env var. Keep it configurable. |
| **Screen translation** | After OCR, route text through translation API (LibreTranslate/google/cloud). Display in same results popup via new "Translate" tab. |
| **Khoj stays optional** | Never a startup dependency. Install separately, point `NOXFLOW_AI_ENDPOINT` at it. |
| **rtk stays optional** | CLI tool, not shell-integrated. Install separately. |

---

## 3. Execution Order (Recommended Sequence)

```
Week 1:   Phase A (Rivendell notifications) + Phase B (Tide-island state machine)
Week 2-3: Phase C (QuickSnip capture) 
Week 3-4: Phase D (Waylandar calendar)
Week 4-5: Phase E (Morphing + Navbar)
Week 5-6: Phase G (Overview + Dashboard/Weather)
Deferred: Phase F (SDF blobs — only after E proves concept)
          Phase H (AI/translation — config is already done, polish later)
```

Each phase is independently revertable via branch. Merge only after: `journalctl --user -u noxflow-shell` has zero warnings, `noxctl` toggles work, `systemctl --user is-active noxflow-shell` returns `active`.

---

## 4. Files to Create vs Modify (summary)

| Action | File | Phase |
|---|---|---|
| Rewrite | `shell/noxflow/components/NotificationItem.qml` | A |
| Modify | `shell/noxflow/surfaces/notifications/NotificationCentre.qml` | A |
| Modify | `shell/noxflow/NoxIsland.qml` | B |
| Modify | `shell/noxflow/surfaces/capture/Capture.qml` | C |
| **Create** | `shell/noxflow/surfaces/capture/WordOverlay.qml` | C |
| **Create** | `shell/noxflow/surfaces/capture/RegionSelector.qml` | C |
| **Create** | `shell/noxflow/surfaces/capture/QuickSnipSettings.qml` | C |
| Rewrite | `shell/noxflow/CalendarModel.qml` | D |
| Modify | `shell/noxflow/surfaces/calendar/CalendarWidget.qml` | D |
| **Create** | `shell/noxflow/surfaces/calendar/CalendarSidebar.qml` | D |
| **Create** | `external/waylandar-backend/sync.py` | D |
| **Create** | `shell/noxflow/MorphRegistry.qml` | E |
| **Create** | `shell/noxflow/components/MorphingSurface.qml` | E |
| **Create** | `shell/noxflow/components/BlobEffect.qml` (shader) | F |
| **Create** | `shell/noxflow/components/BlobGroup.qml` | F |
| **Create** | `shell/noxflow/components/BlobRect.qml` | F |
| Modify | `shell/noxflow/surfaces/overview/Overview.qml` | G |
| Modify | `shell/noxflow/surfaces/dashboard/Dashboard.qml` | G |
| **Create** | `shell/noxflow/services/weather.qml` | G |

---

## 5. Risk Register

| Risk | Mitigation |
|---|---|
| **Wayle still runs** | Phase A.0: stop + disable. Follow the same process as the previous session. |
| **Scroll-overview plugin breaks on Hyprland update** | **Do NOT adopt.** QML-only approach in Phase G uses `Flickable` + wheel events. |
| **OAuth tokens in public repo** | Phase D: `.gitignore` before writing any sync code. Add `*oauth*`, `*token*`, `waylandar-backend/config.json`. |
| **Caelestia SDF blob code is GPL** | You're stealing the CONCEPT (SDF rendering via ShaderEffect), not their C++ plugin. Implement in pure QML — no license conflict. |
| **QuickSnip's dependency on imagemagick + tesseract + wlrctl** | These are optional dependencies. Graceful fallback: "install X for full capture features." |
| **Waylandar's Python backend vs noxd** | Waylandar backend runs as a separate service (`waylandar-sync.service`) — no conflict with noxd. Communicate via FileView cache files. |

---

## 6. Keybinds (current, plan to keep stable)

| Surface | Current key | Phase |
|---|---|---|
| Launcher | `SUPER + Space` | — |
| Capture | `SUPER + SHIFT + S` | C (more powerful but same key) |
| Notifications | `SUPER + N` | A (same key, different animation) |
| Calendar | `SUPER + SHIFT + C` | D (adds sync, same key) |
| Dashboard | `SUPER + D` | G (adds weather, same key) |
| Control Centre | `SUPER + SHIFT + B` | — |
| Overview | `SUPER + W / SUPER + Y` | G (smooth scroll added, same key) |
| Settings | `SUPER + ,` | — |

No keybind changes between phases — only visual/behavioral improvements behind the same triggers.

---

## 7. Current Context for the Next Session

When execution starts:

1. There are 2 shells running: `wayle.service` (active) and `noxflow-shell.service` (active)
2. `waybar.service` is inactive (already handled)
3. The shell compiles with **zero errors, zero warnings** (file-not-found is benign)
4. All 10+ surfaces work: Bar, NoxIsland, Launcher (6 modes), Overview, Capture, Calendar, Dashboard, Settings, ControlCentre, NotificationCentre, RadialWheel
5. Phase 0 fixed: OCR pipeline, clipboard persistence, Bar warnings, Tooltip API, Keys migration, transformOrigin, width/height deprecated, shellRoot id, AI endpoint, NoxIsland validStates guard
6. The plan document `PLAN.md` exists with rollback protocol + testing strategy
7. `REFERENCES.md` exists with pinned commits for all reference repos
8. **Start with Phase A.0: `systemctl --user stop wayle.service && systemctl --user disable wayle.service`**
