# NoxFlow Runtime Error Audit

**Sources:** `journalctl --user -u noxflow-shell -b` and `journalctl --user -u noxd -b`
**Audit date:** 2026-07-28

---

## 1. noxflow-shell: QML Runtime Errors

### 1.1 `forceActiveFocus is not defined` — Capture.qml

```
WARN scene: @surfaces/capture/Capture.qml[545:-1]: ReferenceError: forceActiveFocus is not defined
```

**File:** `shell/noxflow/surfaces/capture/Capture.qml:545`
```qml
forceActiveFocus();
```

**Root cause:** `Capture.qml:545` calls `forceActiveFocus()` on `PanelWindow`
(id: `root`). PanelWindow is a Quickshell window type that does **not** inherit
`Item`, so it has no `forceActiveFocus()` method. The method exists on `Item`
subclasses.

**Impact:** Showstopper warning on every Capture open. 4 occurrences in current
session. Does not prevent Capture from rendering, but the scrim doesn't receive
keyboard focus, so Escape **may not work** consistently.

**Fix:** Replace with `root.focus = true` or use `Qt.forceActiveFocus()`.

---

### 1.2 FileView first-run warning — ClipboardModel

```
WARN scene: QML FileView at @ClipboardModel.qml[81:36]:
  Read of /home/namik/.local/state/noxflow/clipboard.json failed: File does not exist.
```

**File:** `shell/noxflow/ClipboardModel.qml:81`
**Severity:** Benign. The file is created on first clipboard save.

**Fix:** Suppress the warning or check `FileView.exists` before loading.

---

### 1.3 QML Module name warnings (startup only)

```
WARN quickshell.qmlscanner: Module path contains invalid characters for a module name:
  "/surfaces/radial-menu"
WARN quickshell.qmlscanner: Module path contains invalid characters for a module name:
  "/surfaces/control-center"
```

**Root cause:** Directory names contain hyphens (`radial-menu`, `control-center`).
QML modules treat hyphens as invalid for module names.

**Impact:** Cosmetic. The module directories are not declared as QML modules
(the actual surfaces are imported via direct QML file paths in `shell.qml`).

**Fix:** Rename directories to use underscores (`radial_menu`, `control_centre`).

---

## 2. noxd: Daemon Errors

### 2.1 Repeated `Resource temporarily unavailable (os error 11)`

```
{"component":"noxd","event":"internal_failure","level":"error",
 "message":"socket=/run/user/1000/noxflow/noxd.sock; Resource temporarily unavailable (os error 11)"}
```

**Count in current session:** 20+ occurrences (logged every few seconds during
shell restart cycles).

**Timeline:** Clusters around shell restarts (22:02-22:07 and again 04:44-04:45).

**Root cause:** The error `os error 11` is `EAGAIN` / `EWOULDBLOCK` on a
non-blocking accept operation. In `main.rs:918` the daemon checks for
`WouldBlock` and sleeps, but the error logged at `main.rs:909-914` comes from
`handle_client()` — specifically the `stream.set_read_timeout(Some(..))` or
the actual read on the socket. When the shell connects, does a negotiation,
gets subscribed, then disconnects (or the shell crashes), the daemon's
`read_frame()` call on the UnixStream returns `EAGAIN` because the stream's
read timeout fires.

**Impact:** Noisy logs but daemon recovers. However, this error is listed as
`"error"` level, not `"warn"`, making it look like a critical failure.

**Fix:** Downgrade to `"warn"` or handle `WouldBlock` with a proper timeout
sleep instead of treating it as an error.

---

## 3. Shell memory and CPU observations

From `systemctl --user status noxflow-shell noxd`:

| Process | RSS | Peak RSS | CPU time (8h) |
|---------|-----|----------|----------------|
| `quickshell` | 217 MB | 370 MB | 3m24s |
| `noxd` | 23 MB | 31 MB | 5h22m |

**Observation:** noxd has used **5 hours 22 minutes of CPU** over 8 hours of
uptime. This is extremely high for a system state daemon. Likely causes:

- Busy-wait polling in one or more provider threads
- Audio provider's `pactl subscribe` generating high-rate events
- Inefficient event bus dispatch

**Recommendation:** Profile noxd's provider threads. The `pactl subscribe`
subprocess (PID 2216) is a likely culprit.

---

## 4. Service startup failure history

The journal shows multiple shell startup failures during development session
(starting ~22:02):

1. **22:02:37** — `IpcHandler is not a type` (missing Quickshell.Io import?)
2. **22:03:18** — `Duplicate signal name` in NotificationModel (resolved)
3. **22:04:35** — `Type ControlCenter.ControlCentre unavailable` — transitive
   dependency failure: ThemeProfiles.qml declared as singleton but missing
   `pragma Singleton` (resolved)
4. **22:05:22** — `Slider.qml: Cannot assign to non-existent property "value"`
   (resolved)
5. **22:07:14** — `Cannot assign to non-existent property "rightMargin"`
   (resolved)

The shell currently starts successfully (active since 04:45:23). These resolved
errors indicate the component library went through several API fixes to match
the pre-v1.0 Quickshell API surface.

---

## 5. `noxctl surface` command verification

All commands tested with `noxctl <surface>` — each calls
`quickshell ipc -p /home/namik/.config/noxflow/shell/shell.qml call noxctl toggle<Surface>`.

| Command | Exit code | Result |
|---------|-----------|--------|
| `noxctl dashboard` | 0 | Opens/closes |
| `noxctl launcher` | 0 | Opens/closes |
| `noxctl overview` | 0 | Opens/closes |
| `noxctl notifications` | 0 | Opens/closes |
| `noxctl control` | 0 | Opens/closes |
| `noxctl calendar` | 0 | Opens/closes |
| `noxctl settings` | 0 | Opens/closes |
| `noxctl capture` | 0 | Opens/closes |
| `noxctl radial` | 0 | Opens/closes |
| `noxctl dnd` | 0 | Toggles DND (local model) |
| `noxctl system` | 0 | Maps to dashboard |
