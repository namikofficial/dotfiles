# NoxFlow bugs, UI/UX, and completion plan

Date: 2026-09-06. Audited branch: `namik`. Source baseline: `7686037`.

Status: **For user review. No implementation has been authorized by this document.** All work items below remain open. This document records an investigation and defines implementation packets for subsequent agents.

## 1. Scope and evidence

Scope is the NoxFlow desktop experience: QML surfaces, shared controls, shell state and IPC, and the Rust/script integrations those surfaces depend on. This is not a comprehensive audit of the repository's unrelated AI tooling, editor configuration, installation scripts, or every Rust provider implementation.

The audit read current source and checked live service state/logs. It did not interactively exercise every surface, perform transfers, change settings, send notifications, restart services, or run destructive power/network actions. Visual and physical-input acceptance is still required. Source anchors below use paths and function names so they remain useful when line numbers change.

Evidence labels:

- **Confirmed — source:** the inspected code demonstrates the missing path or incorrect logic; the complete graphical journey has not necessarily been reproduced.
- **Confirmed — check:** a bounded check reproduced the specific behavior.
- **Observed — runtime:** current service metadata or journals contain the observation; attribution may still need investigation.
- **Verify first:** a credible risk with a precise reproduction gate. Do not implement a speculative fix before reproducing it.
- **Improvement:** proposed behavior, not a claim that an existing feature is broken.

Baseline results:

| Check | Result and limits |
|---|---|
| Worktree | Branch `namik`; pre-existing modification in `code/vscode-user-settings.json`. Preserve it. |
| Installed shell source | `~/.config/noxflow/shell` resolves to this checkout's `shell/noxflow`. |
| Services | `noxflow-shell.service` and `noxd.service` active; `wayle.service` inactive. Do not execute the old plan's unconditional dual-shell cleanup. Enabled/disabled state was not checked. |
| Notification bus owner | `org.freedesktop.Notifications` owned by `dunst`, confirmed with `busctl --user list`. |
| Reload support | `systemctl --user show noxflow-shell.service -p CanReload` returned `CanReload=no`. |
| Existing JS tests | Hover engagement, protocol fixtures, system snapshot, and workspace presentation tests passed. |
| Launcher contract | `shell/noxflow/tests/test_launcher_contract.sh` passed. This is a source-string contract check, not functional acceptance. |
| Focused calculator check | Extracted the actual `evaluateCalc` function and executed it in Node: `2abc+3 → 5`, `(2+3 → 5`, `2 3 → 2`, `1.2.3+1 → 2.2`; valid `2+3*4 → 14`. |
| Event allowlist check | Loaded actual `Protocol.js`: `transfer` and `settings` absent from `providers`. |
| Logs | Current boot includes a portal app-ID registration warning and missing clipboard file warning. Older September 5 logs include repeated SVG buffer warnings and weather curl exit 35. Historical warnings need fresh reproduction. |

No Rust build/test, full shell lint, graphical smoke run, multi-monitor test, or screenshot acceptance was performed for this documentation-only audit. Passing existing checks does not override the concrete findings below.

## 2. Priorities and execution order

P1 = broken primary behavior, misleading success, stale state, or wrong action/recipient risk. P2 = incomplete workflow, recovery/accessibility gap, or robustness issue. P3 = optional enhancement after correctness. No confirmed P0 was established.

| Packet | Priority | Items | Dependency / ownership |
|---|---|---|---|
| A — IPC and action contract | P1 | NF-01, NF-02 | First; own `Protocol.js`, `NoxdClient.qml`, IPC action contract, central shell dispatch. |
| B — Panel lifecycle | P1 | NF-03, NF-04 | Own `PanelController.qml`, `MorphSurface.qml`; coordinate shell entry changes with A. |
| C — Settings and shared controls | P1/P2 | NF-05, NF-06, NF-18 | Depends on A; own settings panel, tokens, common controls. |
| D — Launcher and radial menu | P1/P2 | NF-07, NF-08, NF-09, NF-19 | Depends on A/B; own launcher and radial surface. |
| E — Capture | P1/P2 | NF-10, NF-11, NF-12 | Independent core work; coordinate focus transitions with B. |
| F — Calendar and weather | P1/P2 | NF-13, NF-14, NF-15 | Own both models, calendar widget, calendar backend; split only with explicit file ownership. |
| G — Notifications and clipboard | P1/P2 | NF-16, NF-17 | Depends on A; first resolve existing integration ownership, then UI. |
| H — Sharing | P1/P2 | NF-20 | Depends on A; own Quick Share and transfer model integration. |
| I — Runtime and acceptance | P1/P2 | NF-21, NF-22, NF-23 | Establish baseline early; finalize after all relevant packets. |
| J — Optional product completion | P3 | NF-24 | Only after review of the desired product scope. |

Future agents may work on independent packets concurrently after approval, with one coordinator reviewing contracts and owning integration. Do not let multiple agents edit `shell.qml`, `NoxdClient.qml`, or shared tokens independently. Prefer small validated commits inside each packet over one large rewrite.

## 3. Detailed findings and required behavior

### NF-01 — Transfer and settings events are discarded before UI delivery

**P1 · Confirmed — source/check.** `shell/noxflow/Protocol.js::providers` omits `transfer` and `settings`. `NoxdClient.qml::handleEvent` returns immediately for providers absent from that list. `shell.qml::onEventReceived` expects transfer events, and `TransferModel.qml::applyEvent` expects discovery/session changes. Initial snapshots can arrive, creating an apparently working but stale interface.

Required work: reconcile the provider registry with the daemon's actual event contract; accept and validate supported events without weakening stream/schema checks. Deliver settings and transfer events to their actual consumers. Check whether merging and both snapshot/event delivery cause duplicate processing. Retain a deliberate policy for unknown providers.

Acceptance: start from an initial snapshot; inject discovery, incoming offer, progress, completion, settings change, unknown-provider, and wrong-stream events through the real client path. UI changes without reconnecting; incoming requests fire once; wrong-stream handling remains intact. Add tests importing production parsing/dispatch logic.

### NF-02 — Visible actions do not match the Rust action contract

**P1 · Confirmed — source.** `core/noxflow-ipc/src/lib.rs::Action` has no `window_focus`, `copy_result`, `clipboard_copy`, `notification_action`, or `toggle_launcher`. These are sent respectively by `Launcher.qml::activateSelected`, its calculator fallback, `ClipboardPanel.qml::copyEntry`, `NotificationCentre.qml::onActionInvoked`, and `RadialWheel.qml::activateSlot`.

Required work: inventory every QML `runAction` literal and dynamically constructed action against the Rust enum and handlers. Route shell-local navigation through the shell controller; route clipboard writes through a real clipboard process/provider; add typed daemon actions only where daemon ownership is appropriate. Handle unit variants consistently with the established serialization adapter. Do not add success-returning placeholder handlers.

Acceptance: window selection focuses the chosen window; calculator activation writes the evaluated value; clipboard copy creates no unsupported-action error; notification actions reach the originating application; radial Launcher opens the launcher. Every failure produces visible feedback and retains a recovery path. Prove effects, not merely successful IPC submission.

### NF-03 — Open is a toggle, and named close can corrupt unrelated state

**P1 · Confirmed — source.** `core/PanelController.qml::open` calls `close(name)` when the named panel is already active without an initial section; `toggle` simply aliases `open`. Explicit `openCalendar`/`openNotifications` IPC methods therefore are not idempotent. `close(name)` clears `activePanel` unconditionally even when a different panel is active.

Required work: define separate open, close, toggle, section-switch, and monitor-retarget semantics. Opening an already open panel keeps it open; closing an inactive named panel leaves the active one alone. Keep animation completion and stale close callbacks tied to the correct panel instance/generation.

Acceptance: `open(A), open(A)` leaves A open; `open(A), close(B)` leaves A active; `toggle(A)` closes A; `open(A), open(B)` produces one interactive major panel. Test interrupted transitions, section switches, and delayed close callbacks.

### NF-04 — Per-monitor panel registrations have no matching cleanup

**P2 · Confirmed — source; hotplug impact verify first.** `shell.qml` registers each MorphSurface under eight panel names. Destruction only unregisters from `SurfaceCoordinator`; `PanelController` has no unregister function. It retains those instance lists and uses them in `surface()` and `closeSurface()`.

Required work: unregister destroyed instances from every owned key, prune invalid references, and retarget/close when the owning monitor disappears. Define what opening the same panel on a second monitor should do; the current active-name branch can close it instead of moving it.

Acceptance: remove/re-add a secondary monitor repeatedly; registry size returns to the expected count, open/close still targets the correct screen, and no destroyed-object access or invisible input layer remains.

### NF-05 — Settings preview is not reconciled with persisted settings

**P1 · Confirmed — source.** `NoxdClient.qml::emitSettingsEvents` constructs `fakeEvent` objects but never emits/applies them. Settings events are also filtered by NF-01. `SettingsPanel.qml` changes tokens immediately and submits persistence without showing acknowledgement/failure. The corner-radius label reads `Tokens.appearanceRadius`, a readonly constant of 14, while buttons change `radiusMd` and other values.

Required work: establish one settings-to-token adapter for initial state, external updates, local edits, and reconnects. Separate preview/pending/saved/error state and reconcile rejected writes. Display selected density/radius/profile from the effective state. Preserve schema validation; inspect existing settings controls before introducing another storage mechanism.

Acceptance: change profile, density, radius, and motion; restart shell and verify each restores. An external `settingsctl` change updates the UI. A failed write cannot silently masquerade as saved. Radius label and selection match the effective radius.

### NF-06 — Settings maintenance buttons lack a working operation path

**P1/P2 · Confirmed — check for reload; other buttons verify first.** `SettingsPanel.qml` requests `systemctl --user reload noxflow-shell`, but the installed service reports `CanReload=no` and the tracked unit has no `ExecReload`. These buttons also use `Quickshell.exec` with a single command string, unlike the launcher’s tracked `Process` path.

Required work: implement supported restart/reload semantics with process exit handling. Verify the installed Quickshell command API and gallery unit before retaining those controls. Show actionable failure; expose unavailable optional operations truthfully.

Acceptance: Reload Shell reaches a fresh loaded shell; Restart Daemon reconnects and restores state; Gallery either opens the actual configured gallery or displays a precise unavailable state. No silent disappearance on failure.

### NF-07 — AI debounce survives reset and accepts obsolete callbacks

**P1 · Confirmed — source.** `Launcher.qml::resetAi` stops `aiTimeout` and aborts `aiXhr` but never stops `aiTimer` or clears `pendingAiQuery`. `onClosed` does not reset AI. Typing three characters and deleting them or changing modes within 400 ms can still send the pending query. Callbacks do not check request identity before modifying shared response/loading state.

Required work: invalidate pending debounce and in-flight requests on reset, short query, close, and mode change. Use a generation/request identity guard in every callback and timer. Make submission policy clear, especially for configurable remote endpoints; consider explicit Enter/Send as the reviewed UX default.

Acceptance: type then immediately erase/change mode/close: no deferred request. Slow A followed by B cannot overwrite B or stop B's timeout. Reopen has a deterministic state. Timeout, HTTP failure, and retry behave visibly.

### NF-08 — Calculator silently evaluates malformed input

**P1 · Confirmed — check.** Actual `Launcher.qml::evaluateCalc` ignores invalid characters, accepts unclosed parentheses, accepts malformed decimals, and does not require all tokens to be consumed. Reproductions are in the baseline table.

Required work: reject invalid characters/numbers and incomplete or surplus tokens; enforce matching parentheses. Define supported operators and precision. Disable copy for invalid expressions and complete the valid-result copy path in NF-02.

Acceptance: valid precedence/unary/parentheses cases work; malformed examples above, divide/modulo by zero, and non-finite results show a clear invalid state. Enter copies exactly the displayed valid result.

### NF-09 — Failed application discovery cannot be retried in the session

**P2 · Confirmed — source.** `Launcher.qml::scanDesktopFiles` sets `scanStarted = true`; subsequent calls return early, including after scanner failure. The scanner stores errors, but there is no rescan path that resets this latch.

Required work: add explicit retry/refresh, distinguish uninitialized/loading/empty/failure states, and define invalidation after app installation or desktop-entry changes. Preserve desktop-ID launching and existing discovery semantics.

Acceptance: fail discovery once, restore the helper, retry successfully without shell restart. A newly installed/removed application is reflected after refresh. No duplicate concurrent scans.

### NF-10 — Capture reports completion before success and mishandles text copy

**P1 · Confirmed — source.** `Capture.qml::performAction` closes copy/save immediately after starting the process. OCR completion sends “OCR Copied” without copying text. `copyText(text)` ignores its argument; `copyToClipboard.onStarted` always writes `root.ocrText`, then disables stdin without re-enabling it for later copies.

Required work: track each capture/copy/save operation through completion and report the real result. Pass the requested text explicitly, reset process stdin per invocation, and distinguish screenshot-image copy from OCR-text copy. Prevent repeat activation while an operation is pending and avoid copying loading/error strings.

Acceptance: perform two different OCR copies in one session and verify clipboard contents; simulate missing `wl-copy`, failed `grim`, and unwritable destination; failures remain recoverable and never say copied/saved. Selected-word copy uses precisely the selection.

### NF-11 — OCR uses multiple live captures and overstates implemented features

**P2 · Confirmed — source; overlay/scale effects verify first.** `Capture.qml::performOcr` captures for text recognition; `ocrProcess.onExited` performs another `grim` capture for TSV after result state changed. The inspected pipeline has grayscale/upscale processing but no dual-polarity comparison despite TASKS.md claiming that feature is real.

Required work: capture one immutable frame and derive OCR text, TSV geometry, and subsequent exports from it. Verify overlay hiding, screenshot completion, scale conversion, and coordinates at 1×/1.25×/2×. Preserve useful existing processing. Implement dual-polarity selection only as an explicitly retained feature, otherwise correct the claim.

Acceptance: a changing underlying window does not change the frame between text and word boxes; boxes align with selected words at all tested scales and monitor offsets. Dependencies, no-text, recognition failure, cancel, and retry have distinct states.

### NF-12 — Image search cannot use a local file URL; upload workflow is incomplete

**P1/P2 · Confirmed — source for local-file search; Lens compatibility verify first.** `Capture.qml::searchCapture` opens a remote image-search URL whose `image_url` is `file:///tmp/nox-capture-search.png`; the remote service cannot fetch that local path. Lens posts raw bytes to a fixed endpoint, writes a fixed HTML result file, and has no visible error/timeout handling. Fixed `/tmp/nox-capture-*` names also allow overlapping sessions to overwrite one another.

Required work: choose a supported browser/upload handoff and verify its present contract during implementation. Explain that the image will be sent to the chosen external service before sending. Use unique private temporary artifacts, bounded process handling, and cleanup after use. Retain a useful save/copy fallback.

Acceptance: a chosen image actually reaches the requested search workflow; cancel sends nothing; offline/HTTP failures are visible; concurrent captures do not share files; temporary image/HTML artifacts are cleaned up. Do not treat opening a browser tab as search success.

### NF-13 — Calendar refresh and failure handling can show stale or empty data as healthy

**P1 · Confirmed — source; same-path FileView reload behavior verify first.** `CalendarModel.qml` disables `watchChanges` and reassigns the identical cache path after sync, without an explicit reload. Its cache loader marks success and clears errors without inspecting `json.errors`. `external/waylandar-backend/sync.py::run_sync` writes fetched events even when the fetch failed, which can replace good cached events with an empty failure result. Writes are non-atomic.

Required work: explicitly reload/watch completed atomic cache replacements; preserve last good data on transient failure; record last attempt separately from last successful sync and surface stale/error states. Resolve the backend from the installation/configuration rather than a hardcoded `~/Documents/code/dotfiles` checkout.

Acceptance: updated fixture events appear after sync without reopening/restarting. A failed fetch preserves previous events and reports stale status. Malformed/partial cache does not erase a healthy view. Installation outside this checkout works.

### NF-14 — Calendar month navigation and multi-calendar semantics are incomplete

**P2 · Confirmed — source.** `CalendarModel.qml::goNextMonth/goPrevMonth` do not clamp `selectedDay`; March 31 → April can retain day 31. `addEvent` mutates an array in place with no persistence. `CalendarWidget.qml::showAgendaForSelected` is empty, although the agenda also uses reactive bindings, so the empty function alone is not proof of a broken agenda. Backend TSV events all receive calendar `primary`, empty description/location, and deduplication by title/date/time can merge distinct events. `eventsForDay` matches only the start date.

Required work: clamp dates, define stable event/calendar identity and multi-day/all-day/time-zone semantics, and make the UI accurately represent the backend's supported sources and horizon. Decide whether local creation is supported before adding a form; if retained, implement reactive updates and persistence. Remove the empty helper only after verifying its callers and existing bindings.

Acceptance: January 31 → February, leap years, year changes, multi-day events, duplicate titles in different calendars, and dates outside the sync horizon behave deliberately. Unsupported dates/sources do not appear as confidently empty. If local creation is retained, it survives restart.

### NF-15 — Weather refresh stops after failure and conditions use a constant icon

**P1/P2 · Confirmed — source; past network failure observed.** `WeatherModel.qml::fetchTimer` is one-shot. Only `parseWeather` restarts it; curl/JSON/no-data failure paths do not. Every condition and forecast gets `☀️`; status starts `available` without a successful observation and has no freshness transition. Historical journals contain curl exit 35; its network cause was not diagnosed here.

Required work: schedule bounded retries after every outcome; retain last good data with age and stale/offline status; validate values before publishing; map actual condition codes and day/night. Make cache-write failures diagnosable without a log storm.

Acceptance: successful fetch → failed fetch → recovered fetch updates without restarting the shell. Fresh install offline shows unavailable, not an invented zero-degree/sunny observation. Rain/night/unknown fixtures render meaningful states.

### NF-16 — Notification centre has no inspected real notification ingress

**P1 · Confirmed — source/runtime ownership; architecture decision required.** The bus owner is Dunst. No `NotificationServer` or application-notification ingestion was found in the inspected shell/daemon paths; daemon provider modules contain no notification provider. Calls to `NotificationModel.addNotification` found in the repository's shell paths are Gallery demo buttons. Notification actions are also unsupported (NF-02). The local model mutates `notifications`/`history` in place; DND discards normal notifications at entry and `timeout || 5000` changes an explicit zero timeout.

Required work: choose one notification owner and a supported integration path. Preserve Dunst until a replacement is ready; do not start competing notification servers. Define active/history/expiration/replacement/action semantics, immutable model updates, and whether DND suppresses presentation while retaining history. Connect NoxIsland and centre to that same source.

Acceptance: real application notification appears, replacement updates the same item, an action reaches the sender, expiration obeys its policy, dismiss/clear update counts immediately, and DND behavior is verified. Restart and bus-owner failure have a defined recovery path.

### NF-17 — Clipboard has two inconsistent product paths

**P2 · Confirmed — source.** Launcher Clipboard intentionally opens Author Clipboard through `hypr/scripts/cliphist-rofi.sh`, with a regression check protecting that choice. The separate shell clipboard panel displays `ClipboardModel` local JSON history; the model explicitly has no watch/automatic capture integration. Its first-save failure creates the directory but does not retry the pending save; duplicate-first-entry timestamp mutation also skips save/notification.

Required work: make Author Clipboard the consistent entry point unless a reviewed shell integration is wanted. Do not silently reintroduce another clipboard watcher. If retaining the local panel, define its source, privacy/retention, loading/error, persistence, and clear-history behavior; remove the unsupported extra action from copy.

Acceptance: all documented clipboard shortcuts lead to an intentional populated workflow; missing external picker has a visible recovery path. If local history is retained, first write/restart, duplicate entry, malformed cache, and delete/clear are verified with non-sensitive fixtures.

### NF-18 — Shared controls can lose bindings and ignore reduced motion

**P2 · Confirmed — source; propagation impact verify first.** `components/Toggle.qml` assigns to its own `checked` property even when callers bind it to provider/token state. That can break the declarative binding after user interaction. Its animations use `durationShort` directly instead of `Tokens.duration(...)`; RadialWheel also uses an unscaled lifecycle duration. Other controls need the same audit, not an assumed blanket rewrite.

Required work: define controlled component behavior: emit requested values and let authoritative state reconcile them, or explicitly support both controlled/uncontrolled modes. Consistently apply reduced-motion/density tokens and accessible name/role/keyboard/focus behavior. Preserve working control contracts.

Acceptance: click a toggle, then change its backing state externally and verify it follows; rejected actions restore authoritative state. Keyboard Space/Enter works once per activation. Reduced motion stops relevant animated movement. Test compact/comfortable/spacious layouts and visible focus.

### NF-19 — Radial labels/hit regions differ from drawn wedge geometry

**P2 · Confirmed — source geometry; visual reproduction required.** `RadialWheel.qml` paints wedges centered on `-π/2 + i*segment`, while labels and mouse hit selection use the interval beginning there, giving a half-segment offset between painted boundaries and interactive regions. `slotCount` is fixed at eight while `loadConfig` accepts arbitrary nonempty arrays.

Required work: use one angle/segment calculation for painting, labels, hover and selection. Validate or derive slot count. Fix the Launcher route with NF-02 and verify application-launch APIs. Define pointer, keyboard, and hold/release behavior; the header claim alone is not acceptance.

Acceptance: each wedge centre/boundary highlights and invokes the displayed item; keyboard and pointer select the same index. Invalid/short/long slot configuration is rejected or rendered safely. No phantom actions in the centre/outside ring.

### NF-20 — Sharing chooses its recipient by a changing array index

**P1 · Confirmed — source.** `QuickShareContent.qml` stores `selectedDeviceIndex`, opens a file picker, and later resolves `transfer.devices[index].id` at picker completion. Discovery can reorder devices meanwhile and send to a different peer. Picker command failures are collapsed into `__CANCELLED__` and stderr is discarded, making missing tools indistinguishable from cancellation.

Required work: select/capture the stable peer ID before opening the picker; verify it is still eligible afterward and show recipient plus file summary before send. Handle picker errors separately from cancellation and use robust path transport. Wire real event updates via NF-01; expose transfer failure/retry/cancel status.

Acceptance: select A, reorder/remove devices while picker is open: never send to B. Missing picker is actionable. Multiple files and whitespace/unusual filenames are preserved. Incoming accept/decline, outgoing cancel, offline peer, partial failure, and completion update without reconnecting. Use test files and consenting test devices.

### NF-21 — Current runtime warnings need attribution, not suppression

**P2 · Observed — runtime.** Current boot reports a portal app-ID registration failure. Older logs show repeated `qt.svg.draw: The requested buffer size is too big, ignoring`. A missing clipboard file appears across multiple boots; the repository allows that warning on first run, but this alone does not prove a persistent-write defect.

Required work: capture a fresh journal boundary, identify the surface/asset/process that triggers each non-benign warning, and prove the user-visible impact or absence of one. For SVGs inspect requested dimensions/sourceSize and fallback behavior. For portal registration inspect actual caller/environment and picker/capture interactions. Do not globally suppress Qt warnings or restart all portals as a substitute for diagnosis.

Acceptance: repeated representative journeys produce zero errors/non-benign warnings. Record the tested boot/time/commit and any infrastructure limitation. First-run cache handling stays distinguishable from recurring failure.

### NF-22 — Smoke tests mutate DND and can report success without checking behavior

**P1/P2 · Confirmed — source.** `tests/smoke/test-noxflow-surfaces.sh` uses `toggleDnd` as a handshake and never restores that value. Its warning regex misses warnings such as the observed SVG warning while claiming no warnings. It tests command exit codes rather than panel state, and its leftover-layer check assumes a specific `xywh: 0 40` geometry. `test_protocol.js` duplicates a `valid` implementation rather than testing production `Protocol.js`.

Required work: use read-only handshake/state probes, trap cleanup on failure, check actual requested/visible/focused/layer state, and cover every current registered surface. Restore any state explicitly mutated by a test. Load production parser/logic in fixtures. Distinguish known first-run warnings precisely. Do not make tests pass by removing the asserted behavior.

Acceptance: deliberately break provider allowlist, panel open semantics, or add a non-benign runtime warning and the relevant test fails. Smoke run leaves DND and other persistent settings unchanged and closes its own test surfaces on interruption. Layer assertions work with varying bar heights, scales, and monitor origins.

### NF-23 — Historical plans and completion claims are no longer reliable

**P2 · Confirmed — source.** TASKS.md says all phases are complete, every feature is real, and the branch is `inspired-rewrite`; the current branch differs and this audit establishes missing integration paths. PLAN_v2.md carries historical live-service assertions and an unconditional instruction to stop/disable fallback services. Source paths/overview architecture have changed since those documents were written.

Required work: after review, mark historical plans as historical and link this remediation tracker. Replace broad completion claims with evidence-backed feature status. Reconcile keybind documentation from canonical Lua and its generator; inspect the actual overview route before planning a nonexistent QML overview rewrite.

Acceptance: documentation identifies current architecture and links each claimed working feature to a verification record. No old host snapshot is presented as current or copied into automatic cleanup instructions.

### NF-24 — Optional UI/UX product improvements after functional repairs

**P3 · Improvement, subject to user review.** These are follow-on proposals; they must not be counted as confirmed defects or used to justify cosmetic rewrites before P1 work.

- Add a consistent capability/status pattern across panels: loading, unavailable dependency, fresh, stale, empty, error, retry. Use SystemModel's existing freshness presentation as a reference to inspect, not a new parallel framework.
- Make keyboard focus order, accessible labels, selected states, scrolling and Escape behavior consistent. Validate long names, large text and all density profiles rather than assuming a fixed laptop layout.
- Add a deliberate confirmation/review step for shutdown/reboot and a recoverable pattern for clear-history actions. Launcher currently dispatches power commands immediately; never exercise them during automated visual acceptance.
- Show operation results near the control that initiated them. Extend the existing Control Centre Wi-Fi pending/recovery pattern carefully to audio, Bluetooth, power profile, wallpaper apply and sharing; do not replace working Wi-Fi logic blindly.
- Improve media/player-empty/disconnected states, wallpaper preview/loading/failure presentation, and Dashboard next actions after a dedicated live walkthrough. No specific rendering defect in those areas was proven in this audit.
- Review advanced capture annotations/translation, calendar source management/reminders, and configurable Dashboard widgets as separate feature decisions. Older roadmap aspirations are not evidence they exist or approval to implement every idea.

Acceptance: each chosen enhancement has a before/after journey and screenshot/input evidence, uses current tokens/components, and has a bounded scope. Defer SDF/morph aesthetic expansion until lifecycle, focus, and performance gates pass.

## 4. Required UI/UX acceptance matrix

Run after relevant fixes, with synthetic data where possible. This is outstanding work, not a list of tests already passed.

| Area | Required journeys |
|---|---|
| Global chrome / panel state | Pointer and keyboard open; repeated explicit open/close; rapid A→B→A; click away; Escape during animation; focus returns to the original app; no transparent input blockers. |
| Monitors and layout | Small laptop viewport, ultrawide where available, mixed scale, secondary monitor at negative coordinates, unplug/replug; keep origin and target on intended monitor. |
| Launcher | All six modes; first open typing; empty/failure/retry; launch success/failure; real window focus; valid/invalid calculator; AI cancel/race; external clipboard. |
| Control Centre | All tabs; audio/mic volume and default device; brightness; Wi-Fi scan/auth/failure/retry; Bluetooth connection; power profile unavailable/rejected. Preserve host networking recovery. |
| Capture | Region selection and cancel; image copy/save; repeated text copy; no OCR text; missing dependencies; scale/word alignment; external search cancel/error. |
| Calendar / weather | Cached and first-run offline; refreshing/error/recovery; month/year boundaries; all-day/multi-day; source visibility/horizon; stale weather and condition icons. |
| Notifications / island | Real ingress, replacement, action, DND, timeout, dismissal/history; media/volume/brightness interrupt and restore; notification while another panel has focus. |
| Clipboard / sharing | Consistent picker/history owner; copy result; discovery reorder; unavailable peer; file picker error; incoming/outgoing success/cancel/failure. |
| Settings / wallpaper / Dashboard / media | Save/restart/external settings update; selected styling; wallpaper apply failure; unavailable telemetry/player; long labels and overflowing content. |
| Radial / overview | Correct wedge-to-action mapping and keyboard selection; inspect actual Hyprland overview route, keybind behavior and return focus. |
| Accessibility / motion | Tab and Shift+Tab order; visible focus; Enter/Space activation; disabled actions; accessible names; reduced motion; density changes and text clipping. |

Attach relevant before/after screenshots to implementation evidence, but a screenshot alone cannot establish command success, persistence, correct recipient, focus restoration, or notification action delivery.

## 5. Agent execution contract

After user approval, give each agent one packet and the following instructions:

> Read AGENTS.md, RTK.md, and this plan. Verify current branch, HEAD and dirty state. Reproduce the assigned findings against current source; report findings that have already been fixed or cannot be reproduced. Implement the smallest coherent repair within the assigned file ownership. Preserve current architecture and unrelated changes. Add meaningful behavior tests for the repaired failure paths, run relevant repository gates, and perform required live acceptance where available. Report exact changed paths, tests, runtime evidence, unresolved limitations and commit IDs. Do not mark untested UI or device behavior complete. Coordinate shared-file edits with the main agent. Do not execute other packets or optional P3 work implicitly.

For each item maintain this review record in the implementation follow-up:

```text
ID / owner / status:
Reproduction and baseline:
Root cause:
Changed paths and behavior:
Automated checks:
Live UI/input/device checks:
Screenshots or journal interval:
Remaining limitations:
Commit:
Reviewer decision:
```

Useful validation commands (follow repository instructions and prefix with `rtk`):

```sh
rtk git status --short
rtk git branch --show-current
rtk cargo check --workspace
rtk cargo test --workspace
rtk proxy ./setup/check-shell.sh --all
rtk proxy node shell/noxflow/tests/test_protocol.js
rtk proxy node shell/noxflow/tests/test_hover_engagement.js
rtk proxy node shell/noxflow/tests/test_system_snapshot.js
rtk proxy node shell/noxflow/tests/test_workspace_presentation.js
rtk proxy bash shell/noxflow/tests/test_launcher_contract.sh
rtk proxy systemctl --user restart noxflow-shell.service
rtk proxy journalctl --user -u noxflow-shell.service --since '<recorded-start-time>' --no-pager
rtk proxy ./setup/generate-keybind-docs.py
rtk proxy ./setup/check-keybind-docs.sh
rtk git diff --check
rtk git diff --cached --check
```

Run Rust gates after Rust changes, shell gates after shell changes, and regenerate keybind docs only when their canonical bindings/documentation are in scope. Run repaired surface smoke tests only after NF-22 is addressed or their state mutations are explicitly controlled. Match source validation with live binary provenance when changing daemon/CLI code; a QML restart does not rebuild Rust binaries.

## 6. Completion and rollback gates

- Do not label a packet complete until each assigned acceptance criterion has passed or is explicitly reported as outstanding for review. “Code exists,” IPC accepted, static strings present, or a passing build is insufficient for UI completion.
- Preserve `PanelController`/`MorphSurface` ownership, the launcher’s existing island host, Author Clipboard's intentional route, and working provider logic unless a demonstrated requirement changes them.
- Keep desktop notification ownership, networking, and power actions controlled during testing. Never launch Wayle alongside NoxFlow or replace the current notification owner before its replacement is ready.
- Stage exact intended paths, inspect staged diff, run `git diff --cached --check`, and create atomic validated commits. Do not include the user's unrelated VS Code settings change.
- A rollback should revert the affected implementation commit(s) through a reviewed follow-up and restore affected service configuration where necessary. Do not reset the worktree or erase unrelated changes.
- Final handoff must distinguish source/unit results, local running shell results, physical input, multi-monitor/device results, and external service results. Finish by updating item statuses and historical documentation with evidence rather than declaring every feature real.
