# NoxFlow Recovery Roadmap

**Audit date:** 2026-07-28
**Branch:** `inspired-rewrite` · **Commit:** `0667abd5`
**Pre-audit TASKS.md claim:** "All phases complete. 0 errors, 0 non-benign warnings."
**Audited reality:** See `FEATURE_REALITY.md`, `IPC_MISMATCH.md`, `RUNTIME_ERRORS.md`.

---

## Principles

1. **Fix first, then build.** No new features until the IPC pipeline is reliable,
   runtime errors are zero, and phantom actions are removed.
2. **One phase per commit.** Every phase targets exactly one system and is
   independently revertable.
3. **Truth in labelling.** Update TASKS.md status column only after verification.
4. **No new stubs.** Every new component must handle loading, error, and empty
   states. No "TODO", "FUTURE", "stub" or hardcoded placeholders.
5. **No percentages.** This roadmap has completion gates, not estimates.

---

## Phase 0 — Fix the IPC Pipeline (immediate, break-fix)

### Scope
Eliminate all proven IPC failures: broken action names, phantom actions, and
the single-request bottleneck in NoxdClient.

### Files to modify
- `shell/noxflow/NoxdClient.qml`
- `shell/noxflow/NoxIsland.qml`
- `shell/noxflow/surfaces/capture/Capture.qml`
- `shell/noxflow/surfaces/launcher/Launcher.qml`
- `shell/noxflow/surfaces/notifications/NotificationCentre.qml`
- `shell/noxflow/surfaces/radialmenu/RadiualWheel.qml`
- `core/noxflow-ipc/src/lib.rs` (if adding missing actions)

### Implementation sequence

1. **NoxdClient queue** — Replace single `pending` with a FIFO request queue.
   Add response timeout (5s), remove `pending` blocking.
   ```
   NoxdClient.qml:108 — instead of return false, enqueue
   NoxdClient.qml:117 — after writing, set timeout timer
   ```

2. **Fix NoxIsland action names** (IPC_MISMATCH.md §2a, §2b):
   - `NoxIsland.qml:255-256`: `volume_set` → `audio_set_volume` with `target: "output"`
   - `NoxIsland.qml:259-260`: `brightness_set.value` → `brightness_set.percentage`

3. **Add missing daemon actions or remove from QML** (IPC_MISMATCH.md §3):
   - `window_focus`: Add `WindowFocus { address: String }` to Action enum,
     dispatch through hyprland provider
   - `notification_action`: Add `NotificationAction { id: u32, action: String }`
     to Action enum, emit through notification provider
   - `ai_query`: Add `AiQuery { text: String }` to Action enum, or leave as
     client-side-only XHR call (currently handled entirely in Launcher)
   - `toggle_launcher`: Remove from RadialWheel.qml — it's a QML-internal toggle
     that should use `shellRoot.toggleLauncher()`, not IPC

4. **Fix Capture.qml:545** — `forceActiveFocus is not defined`
   - Replace with `Qt.forceActiveFocus()` or `root.focus = true`

### Prerequisites
None — all changes are local to the indicated files.

### Risks
- Adding `WindowFocus` to the daemon requires understanding the hyprland provider's
  window address format. If the address format is wrong, the action silently fails.
- Notification actions need a notification store on the daemon side (currently
  `NotificationModel` is entirely client-side).

### Tests
- `grep -rn 'runAction(' shell/noxflow/` — verify no more broken action names
- `noxctl launcher && noxctl dashboard && noxctl capture` — verify toggle loop still works
- `journalctl --user -u noxflow-shell -b --no-pager | grep -i error` — zero errors

### Rollback
Revert the commit for this phase. It touches 6 QML files and 1 Rust file.

### Definition of Done
- `runAction()` queued requests don't block each other
- NoxIsland volume/brightness sliders commit to daemon (verified by watching noxd logs)
- Zero phantom actions sent to daemon
- `ReferenceError: forceActiveFocus is not defined` gone from journal
- All `runAction()` calls in QML are cross-referenced against the Action enum

---

## Phase 1 — Protocol and Model Correctness

### Scope
Document the IPC protocol, fix NoxdClient's error handling gaps, reconcile
model property names with daemon snapshot fields.

### Files
- `docs/PROTOCOL.md` (new)
- `shell/noxflow/NoxdClient.qml`
- `shell/noxflow/Protocol.js`
- `shell/noxflow/ModelUtils.js`
- All `*Model.qml` files (validate `applySnapshot` signatures)

### Implementation sequence

1. **Write PROTOCOL.md** — Document:
   - Wire format (version, request/response/event envelopes)
   - All supported methods
   - All Action variants with shapes
   - All provider names and their snapshot data fields
   - Subscription mechanism

2. **Add response timeout to NoxdClient** — `socket.write()` timer, if no
   response within 5s, clear pending and set errorText.

3. **Audit all `applySnapshot()` calls** — Verify field names match what the
   daemon's provider data actually contains. The daemon's `BTreeMap<String, Value>`
   data has no schema enforcement — drift is silent.

4. **Add NoxdClient `connected` signal-based guard** — surfaces that depend on
   daemon should grey out or show a "disconnected" indicator when noxd is down.

### Prerequisites
Phase 0 must be complete (so IPC is reliable enough to test against).

### Risks
- Protocol version mismatch between shell and daemon (currently both at v1)
- Daemon snapshot data shape changes in the Rust code may break QML bindings

### Tests
- Disconnect noxd (`systemctl --user stop noxd`), verify shell surfaces handle
  gracefully (no crashes, show disconnected state)
- Reconnect, verify state syncs within 2 seconds

### Definition of Done
- PROTOCOL.md covers every action and provider
- No `applySnapshot()` silently accepts mismatched fields
- Shell gracefully degrades when noxd is down

---

## Phase 2 — Runtime Error Zero

### Scope
Fix every error/warning in `journalctl --user -u noxflow-shell -b`.

### Files
- `shell/noxflow/surfaces/capture/Capture.qml:545`
- `shell/noxflow/ClipboardModel.qml:81` (suppress first-run warning)

### Implementation sequence
1. Fix `forceActiveFocus` (already in Phase 0, duplicate check)
2. Suppress clipboard FileView first-run warning or pre-create the file
3. Fix module path hyphen warnings by renaming directories:
   - `surfaces/radial-menu/` → `surfaces/radialmenu/` (already exists at radialmenu?)
   - `surfaces/control-center/` → `surfaces/controlcenter/` (already exists)

### Definition of Done
```
journalctl --user -u noxflow-shell -b --no-pager | grep -c 'ERROR'
→ 0
journalctl --user -u noxflow-shell -b --no-pager | grep -c 'WARN'
→ 0 (except benign FileView first-run)
```

---

## Phase 3 — NoxIsland FSM Correctness

### Scope
Replace the if/else `show()` priority chain with a verified FSM. Fix the
duplicate state enum (10 states declared, `priorityMap` has 10 entries, but
`handleEvent()` has no coverage for `notification`/`timer`/`recording` from
daemon events — these are only triggered manually).

### Files
- `shell/noxflow/NoxIsland.qml`
- `shell/noxflow/NoxIslandState.js` (new — testable FSM logic)
- `shell/noxflow/tests/test_noxisland_state.js` (new)

### Implementation sequence
1. Extract state machine to pure JS (no QML dependencies)
2. Write Node tests for all state transitions
3. Replace `show()` priority logic with FSM calls
4. Wire notification daemon events to `showNotification()`

### Prerequisites
Phase 0 (IPC reliability), Phase 1 (protocol documentation).

### Risks
- The priority queue uses `.concat()` + `.sort()` which is O(n log n) per
  insertion for a fundamentally O(1) operation. Fixing this is a performance
  improvement, not correctness.

### Tests
- Node tests for FSM: every valid transition, every invalid transition
- `stateQueue` must not grow unbounded (current max: from enqueue, no cap)

### Definition of Done
- FSM logic is pure JS and tested
- NoxIsland state transitions are deterministic
- `showNotification()` responds to daemon notification events

---

## Phase 4 — Component and Design-System Cleanup

### Scope
Consolidate the component library: remove unused components, fix inconsistent
property APIs, add missing accessible names.

### Files
- `shell/noxflow/components/*.qml`
- `shell/noxflow/theme/Tokens.qml`
- `shell/noxflow/theme/ThemeProfiles.js`
- `shell/noxflow/theme/ThemeProfiles.qml`

### Implementation sequence
1. Remove unused components (check `grep -r` usage across all surfaces)
2. Standardize property names (`checked` vs `on`, `label` vs `text`, etc.)
3. Add missing `Accessible` roles
4. Ensure all theme token references use `Theme.Tokens.*` consistently

### Definition of Done
- Every component is used by at least one surface
- No two components use different names for the same property
- `Accessible.name` on every interactive element

---

## Phase 5 — Real Morphing Engine

### Scope
Replace the stub `MorphRegistry.qml` with a working geometry animation engine.
This is the largest single feature and is deferred to Phase 5 because it depends
on all surface toggle/open/close protocols being stable first.

### Files
- `shell/noxflow/MorphRegistry.qml`
- `shell/noxflow/MorphingSurface.qml` (new — animated geometry wrapper)
- `shell/noxflow/MorphTarget.qml` (new — per-target descriptor)
- `shell/noxflow/surfaces/notifications/NotificationCentre.qml`
- `shell/noxflow/surfaces/controlcenter/ControlCentre.qml`
- `shell/noxflow/surfaces/calendar/CalendarWidget.qml`

### Implementation sequence
1. `MorphTarget.qml` — holds source rect, dest rect, animation duration, easing
2. `MorphingSurface.qml` — wraps a surface, animates x/y/width/height/radius
   from chip geometry to panel geometry
3. Register NotificationCentre, ControlCentre, CalendarWidget with MorphRegistry
4. On open: read chip source rect from registry, animate out
5. On close: animate back to chip rect
6. All morphs are interruptible (animation is cosmetic, never gates input)

### Prerequisites
Phases 0-3 (stable IPC, reliable surface toggles, correct models).

### Risks
- PanelWindow may not support dynamic geometry changes mid-animation
- Quickshell's pre-v1.0 API may change rendering behaviour
- Multi-screen: a chip on monitor 1 cannot morph to a panel on monitor 2

### Definition of Done
- Clicking a Bar chip grows it into its panel
- Closing a panel shrinks it back to the chip
- All surface toggles still work identically
- Reduced-motion setting disables morph animations

---

## Phase 6 — Capture Pipeline Reliability

### Scope
Fix the known broken parts: duplicate tesseract invocation, Lens upload,
Search image, and analysis race.

### Files
- `shell/noxflow/surfaces/capture/Capture.qml`
- `shell/noxflow/surfaces/capture/QuickSnipSettings.qml`

### Implementation sequence
1. **Single tesseract pass** — Request TSV output in the first tesseract call.
   Extract both text body and word coordinates from one TSV output. Remove the
   second tesseract process entirely.
2. **Fix Lens upload** — Google Lens does not have a documented upload API.
   Either remove the button or file a real upload to Google Images.
3. **Fix Search image** — Upload to a temporary paste service or use local
   image search (e.g., `tesseract OCR → Google Text search`).
4. **Fix analysis race** — Move `analyzeText()` call after TSV parse completes,
   or merge it into the single-pass pipeline.

### Prerequisites
Phase 0 (stability) recommended.

### Definition of Done
- One tesseract process per OCR invocation, not two
- No `file://` URLs passed to browser for image search
- `analyzeText()` runs after text is available, not before

---

## Phase 7 — Remaining Surface Fixes

### Progressively fix in any order:

| Surface | Issue | Fix |
|---------|-------|-----|
| Dashboard | Git stub | Wire real `git status` via Process or noxd git provider |
| Weather | Hardcoded icon | Map wttr.in weather code to Unicode/emoji |
| Clipboard | No auto-capture | Add `wl-paste` watch or noxd clipboard provider |
| Launcher | Calculator `new Function()` | Replace with safe expression evaluator |
| Calendar | Error display | Show `lastError` in UI, not just property |
| NotifCentre | `notification_action` phantom | Wire to daemon or remove action buttons |
| Settings | Profile persistence | Wire `setSetting` to actual persistent store |
| Theme | No dark/light toggle | Add color scheme switching |

---

## Phase 8 — Hardening

### Scope
Non-functional improvements: test coverage, error handling, multimonitor
correctness, noxd resource usage.

### Items
- Add `shell/noxflow/tests/*.js` Node tests for Protocol.js, ModelUtils.js
- Add runtime smoke test (restart shell, check journal for errors)
- Profile noxd CPU usage (5h22m CPU over 8h uptime needs investigation)
- Verify all surfaces on multimonitor hotplug
- Add `docs/screenshots/` for visual regression detection
