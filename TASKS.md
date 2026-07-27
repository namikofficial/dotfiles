# NoxFlow Refactor — Task Board

**Branch:** `inspired-rewrite`
**Goal:** Transform dotfiles into a cohesive NoxFlow desktop shell by cloning architectural patterns from reference repos.

---

## Active Tasks

### T1 — Expand component library (Caelestia steal)
**Phase:** 1.1 | **Priority:** High | **Status:** 🔵 In Progress

Steal these from Caelestia Shell:
- [x] Create `components/Elevation.qml` — drop-shadow effect for depth
- [ ] Add `components/StateLayer.qml` — Material 3 state layer pattern for all controls
- [ ] Add `components/Divider.qml` (already exists but check vertical variant)
- [ ] Create `surfaces/` directory structure (bar, island, launcher, control-center, notifications, overview, dashboard, capture, radial-menu, settings)
- [ ] Add `components/MaterialIcon.qml` — icon component supporting Material Symbols
- [ ] Add `components/TextInput.qml` — themed text input field

**Acceptance:** All new components render correctly in Gallery.qml

### T2 — Control centre surface
**Phase:** 1.3 | **Priority:** High | **Status:** ⏳ Pending

- [ ] Create `surfaces/control-center/ControlCentre.qml` — QUIC toggles (WiFi, BT, DND, night light)
- [ ] Add audio mixer with device selection
- [ ] Add brightness slider
- [ ] Add power profile selector
- [ ] Connect all toggles to noxd actions
- [ ] Wire `Super + A` keybind
- [ ] Add morphing panel animation

**Acceptance:** `Super + A` opens a control centre panel with functional toggles

### T3 — Nox Island morphing + FSM
**Phase:** 1.4 → 2.1 | **Priority:** High | **Status:** ⏳ Pending

- [ ] Introduce `islandState` property (normal, volume, brightness, media, mic, recording, timer, notification)
- [ ] Replace current `show()` with state-driven Loader swapping
- [ ] Add smooth morphing between states (expand/contract, crossfade)
- [ ] Add auto-hide with gesture strip
- [ ] Add media expanded layer (album art + controls)
- [ ] Add timer feature
- [ ] Add recording indicator

**Acceptance:** Volume/brightness/media changes morph smoothly, auto-hide works

### T4 — Notification centre
**Phase:** 1.2 | **Priority:** High | **Status:** ⏳ Pending

- [ ] Add notification provider to noxd (FreeDesktop D-Bus listener)
- [ ] Create `surfaces/notifications/NotificationCentre.qml`
- [ ] Add grouped-by-app notifications
- [ ] Add DND toggle + schedule
- [ ] Add clear-by-group
- [ ] Add notification history
- [ ] Wire `Super + N` keybind

**Acceptance:** `Super + N` shows notification centre with history

### T5 — Radial shortcut wheel
**Phase:** 2.2 | **Priority:** Medium | **Status:** ⏳ Pending

- [ ] Create `surfaces/radial-menu/RadialWheel.qml` — Canvas-based 8-slot wheel
- [ ] Add hold-to-open via Super+Tab (long-press vs tap for overview)
- [ ] Add zero-click edit mode
- [ ] Add wheel.json config at `~/.config/noxflow/radial.json`
- [ ] Add slot assignment via launcher

**Acceptance:** Hold Super+Tab shows wheel, release launches app

### T6 — Capture/OCR/Lens workflow
**Phase:** 3.1 | **Priority:** Medium | **Status:** ⏳ Pending

- [ ] Create `surfaces/capture/Capture.qml` — region selector overlay
- [ ] Add grim -> tesseract -> result pipeline
- [ ] Add dual-polarity OCR scoring
- [ ] Add interactive word overlay
- [ ] Add toolbar (copy, save, OCR, translate, Lens, search)
- [ ] Wire `Super + Shift + S` keybind

**Acceptance:** Screen region → OCR text appears → actions available

---

## Queued Tasks

### T7 — Universal launcher (DMS + Caelestia)
**Phase:** 2.3 | **Priority:** Medium

### T8 — Workspace overview (end-4 + scroll-overview)
**Phase:** 2.4 | **Priority:** Medium

### T9 — Calendar integration (Waylandar)
**Phase:** 3.2 | **Priority:** Medium

### T10 — Dashboard (end-4 + weather post)
**Phase:** 3.3 | **Priority:** Medium

### T11 — Theme profiles + AI integration
**Phase:** 4 | **Priority:** Low

### T12 — Cleanup & migration
**Phase:** 5 | **Priority:** Low

---

## Legend
- 🔵 In Progress
- ⏳ Pending
- ✅ Completed
- ❌ Blocked
