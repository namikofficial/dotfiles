# NoxFlow + workstation repair plan

Status: implemented, with **one recorded deviation** (Phase 2's line-count
target, measured in section 0.5) ·
Written 2026-10-09 · Supersedes: `PLAN.md`, `PLAN_v2.md`,
`theplan.md`, `TASKS.md`, `OPENCODE_TASK.md`, and the open items of
`docs/NOXFLOW_BUGS_UX_COMPLETION_PLAN.md`.

This is now the **only** NoxFlow plan. Each item has a verdict, an owner file,
and an acceptance check. Evidence comes from a static audit of all 104
NoxFlow files plus live probes against `noxd`. Claims marked *probed* were
executed on this machine on 2026-10-09.

---

## 0. Already done (2026-10-09)

| Item | Result |
| --- | --- |
| VS Code SOPS decrypt-on-open | Root cause: commit `8495098` (2026-09-06) deleted `sops.*` and `*.env.sops → dotenv` from `code/vscode-user-settings.json`. Restored, corrupted `yaml.disableSchemaDetection` entry repaired, and a guard added to `setup/check-stale-references.sh`. |
| Archived project cleanup | `workspace`/NoxCRM, `nox-billings` and `nox-tickets` are gone from aliases, android env, backup scripts, the desktop palette, docs and CLAUDE.md. A stale-reference guard was added. |
| NoxOrigin helpers | `nox`, `nox-docs`, `nox-web`, `nox-edit`, `nox-just`, `nox-up/down/status/logs`, `nox-env-edit`, `nox-env-sops`, `nox-env-validate`, `nox-help`. `nox-env-validate` passes for all 4 encrypted files (*probed*). |
| Pending, user | **Rotate staging secrets exposed in an agent session:** the `noxorigin_staging_app` and `noxapps_admin` DB passwords and `CURSOR_SECRET`. Then `nox-env-edit staging`, save, `nox-env-validate`, deploy. |
| Pending, user | Reload VS Code, run `nox-env-edit staging`, and confirm the language reads `dotenv` and the values are plaintext. |

---

## 0.5 Progress log

### Phase 1 — done (2026-10-09)

All 14 items implemented. Gate green (14/14 checks), surface smoke test 23/23,
all 14 shell suites pass.

Decisions 3, 4 and 10 landed as new files:

- `shell/noxflow/config/Apps.qml` — the external-program registry. One
  `command -v` sweep at boot; a missing binary disables its entry with a
  tooltip instead of failing silently. `setup/check-noxflow-binaries.sh`
  enforces it in the gate.
- `shell/noxflow/services/AiClient.qml` — the single AI path. Reads
  `ai.endpoint` / `ai.model` / `ai.provider` from noxd settings. The launcher
  is now a thin adapter over it and no longer holds an `XMLHttpRequest`.
- `shell/noxflow/config/Appearance.qml` — one owner for mapping a settings map
  onto Tokens, called by both the Settings panel and boot-time hydration.
- `shell/noxflow/tests/run-all.js` — the gate now runs all 14 suites, not one.

Verified live, not just statically: setting `appearance.profile` to `focus`,
restarting, and observing `shell: applied persisted appearance:
appearance.profile` in the journal is the acceptance check for item 1.12.

Audit findings confirmed by probe: `dunstctl get-paused` does not exist
(`is-paused` does); `Quickshell.exec` does not exist in 0.3.1 (only
`execDetached`); `thunar`, `zenity`, `magick` and `gnome-control-center` are
all absent from this machine.

### Phase 2 — done (2026-10-09)

Nine files deleted outright: `Gallery.qml`, `components/MorphingSurface.qml`,
`components/StateLayer.qml`, `BatteryModel.qml`, and the five unreferenced
`surfaces/island/activities/*.qml`. Plus `MorphRegistry.registerChip`/
`unregisterChip`/`chipRect`, `HoverEngagement.OSD_KINDS`, the sync pill, the
eight uncalled `NoxIsland.show*` entry points and their backing properties, and
the `calendar`/`clipboard` snapshot branches that called an `applySnapshot`
those models never had.

Two duplicate OSD producers collapsed to one (volume, brightness, output-mute,
input-mute now come only from the AudioModel/BrightnessModel signals).

Three defects found and fixed while deleting:

1. **The notification pill rendered fake data because the daemon has no
   notifications provider.** `EventBus::subscribe` does not validate provider
   names — an unknown name is acknowledged and then never delivers an event.
   `notifications`, `calendar` and `clipboard` were all in the shell's
   allowlist with no corresponding module under `core/noxd/src/providers/`.
   Removed from `Protocol.js`, and `test_protocol.js` now asserts the
   allowlist lists real providers and rejects phantoms.
2. **A hardcoded volume max of 100** made the OSD bar overflow on any system
   whose Pipewire range differs. Now reads `audio.maxVolume`.
3. **The 250 ms geometry poll** now runs on change signals only
   (`audio.outputVolume`, `updates.count`, `media.status`, workspace changes,
   bar width) behind a 100 ms coalescing timer.

`NotificationModel` is a plain `QtObject`, so its `var` list property emits no
change signal. Noted rather than "fixed" with a redundant signal — Qt rejects
the explicit override.

Two pre-existing Rust failures were blocking the gate and are fixed: `cargo
fmt` drift in `bluetooth.rs`, `tests/server.rs` and `noxflow-ipc/src/lib.rs`,
and four clippy lints (`needless_borrow`, `unnecessary_get_then_check`, two
`unnecessary_map_or`). `check_ipc_docs` was also tripping on whitespace-only
diffs; it now compares through `rustfmt` so it fires on semantic changes only.

`docs/IPC_PROTOCOL.md` gained a "Subscribing to providers" section documenting
that the daemon does not validate provider names — that is why the phantom
subscriptions looked healthy.

Line count is flat rather than down 1,500. Phase 1 added ~450 lines of
registry, AI client, appearance helper and tests; Phase 2 removed ~700. The
remaining reduction has to come from Phases 3 and 4, where `ControlCentre.qml`
(1,555 lines) and `NoxIsland.qml` (1,208) are split.

### Phase 3 — split, then repaired (2026-10-09)

The split landed `bar/` and `island/`, but **the shell did not start at all**
and every static suite still passed. Seven defects, all invisible to `qmllint`
and to the existing tests:

| # | Defect | File |
| --- | --- | --- |
| 3.a | `SystemTray { }` — it is a non-creatable **singleton**, so the shell died with "Element is not creatable" | `bar/TrayCapsule.qml` |
| 3.b | `delegate: WorkspacePill` with no namespace qualifier | `bar/WorkspaceCluster.qml` |
| 3.c | `function escape()` — an illegal QML method name (now `handleEscape`) | `island/IslandEngagement.qml` |
| 3.d | A `QtObject` root cannot hold `Connections` children — no default property (now an `Item`) | `island/IslandEvents.qml`, `IslandEngagement.qml` |
| 3.e | `readonly property var ICONS` — QML properties may not start upper-case | `island/IslandCard.qml` |
| 3.f | A dropped property block: the host referenced ~15 properties it never declared, plus a duplicate `hoverEngaged` | `island/IslandHost.qml` |
| 3.g | `root.workspaces` / `root.pollTimer` — ids, not properties of `root` | `bar/Bar.qml`, `bar/MicIndicator.qml` |

`qmllint` reports **nothing** for any of them: it cannot resolve the Quickshell
C++ module imports, so it silently skips the whole file. The gate now also runs
`setup/check-noxflow-load.sh`, which actually loads the config.

> **That check must never run `quickshell -p` while the live shell is up.** It
> starts a second shell process, which registers its own layer-shell surface and
> draws a second top bar until it is killed. It was written that way first, and
> it did exactly that. It now restarts `noxflow-shell.service` instead and reads
> the result from the journal, so the screen never holds two shells at once.

The split is now: `IslandHost` (state machine) + `IslandState`, `IslandQueue`,
`IslandQueueHost`, `IslandPanelYield`, `IslandRouter`, `IslandEngagement`,
`IslandEvents`, `IslandTimers`, `IslandCard`, `IslandCardHost`, `IslandLayers`.
`IslandHost.qml` went 1146 → **350** lines; no file in `bar/` or `island/` is
over 350 (next largest: `IslandCard.qml` 317, `IslandEngagement.qml` 309,
`Bar.qml` 302). It briefly reached 382 during the Phase 1 re-verification and
was brought back under with `IslandProducers.qml` — see 0.5.

> **This list is load failures only.** The split also introduced behavioural
> defects that load cleanly and pass every suite, because they are binding
> semantics rather than syntax: three components wired in the wrong direction,
> a dropped `implicitHeight`, and dropped `calendarWidget.open()`/`close()`.
> They are recorded under 0.5 → *Phase 1 re-verification*, and
> `test_island_contract.sh` now guards them.

---

### Phase 3.5 — the lists were all empty (2026-10-09)

With the shell running, the bar showed **no workspaces at all**. Three more
independent bugs, stacked:

1. **`Array.isArray` rejects daemon lists.** noxd snapshots reach QML as QML
   *sequence* objects. They report `constructor === Array` and a correct
   `length`, but `Array.isArray()` returns **false** — so every
   `Array.isArray(x) ? x : []` guard silently replaced live data with `[]`.
   Affected: workspaces, windows, monitors, audio outputs/inputs/streams, media
   players, Wi-Fi list, IP lists, VPN, power profiles, Bluetooth adapters and
   devices, Syncthing folders/devices, transfer devices/sessions, notification
   items. `noxctl status` reported every provider as `Available` throughout.
   Fixed by `ModelUtils.asArray()`, which accepts anything array-like; covered
   by `tests/test_model_utils.js`.
2. **The workspace strip hid itself.** `WorkspaceCluster`'s `Flickable` had
   `visible: contentWidth > width`, i.e. it disappeared exactly when the content
   *fit* — the normal case. It should gate `interactive`, not `visible`.
3. **`Tokens.iconFont` named a font that is not installed.**
   `"Symbols Nerd Font Mono"` fell back to Noto Sans Mono, which has no Nerd
   Font codepoints, so every icon rendered as a wrong glyph — the island clock
   drew a stray circle over its own label. The only Nerd Font family installed
   is `JetBrainsMono Nerd Font`. This also completes decision 10: the literal
   was still hardcoded in 9 further files, all now `Theme.Tokens.iconFont`.

Island card fixes: its `width` binding measured `islandContent.implicitWidth`
while that row was `anchors.fill: parent` — circular, so the card settled on its
minimum pill width and the label overflowed onto the icon. Widths are now fixed
per state and the label elides. The progress bar was drawn in idle (its
`activityMaximum > 1` guard is true by default) — that was the stray underline
under the clock; it is now gated on kinds that report a value.

### Phase 6 — done (2026-10-09)

**`shell/noxflow/tests/test_action_contract.js`** (new) enumerates every action
name at every `runAction(`/`sendAction(` call site and requires each to exist in
the daemon's `Action` enum. This is the general form of the four-name denylist
in `test_action_routing.sh`. Verified by re-injecting the historical
`ai_query` defect: the test failed with the file and line, then passed again
once reverted.

**Two new Rust tests in `core/noxflow-ipc`**:

- `qml_payload_shapes_decode` — the name check does not catch a *shape* error.
  A renamed or missing field (`brightness_set` carrying `value` instead of
  `percentage`) makes serde reject the whole request, so the button dies while
  the name test still passes. 32 literal payload shapes from the call sites.
- `unit_variant_actions_decode_in_both_forms` — pins the probe result that
  `{"media_next":{}}` and `"media_next"` both decode, so the rejected audit
  claim in section 3 cannot come back.

Shell suites 16/16, `noxflow-ipc` 16/16, clippy clean.

> **`qmllint` is not the check item 6 asked for.** It passes a config whose
> every component fails to instantiate: it cannot resolve the Quickshell C++
> module imports, so it silently skips the file and exits 0. It reported nothing
> for the seven defects that stopped the shell from starting.
> `setup/check-noxflow-load.sh` supersedes it — it actually loads the config —
> and `release-gate.sh` runs both.

### Phase 7 — done (2026-10-09)

- `PLAN.md`, `PLAN_v2.md`, `theplan.md`, `OPENCODE_TASK.md`, `TASKS.md` and the
  338 KB `session-ses_05bd.md` moved to `docs/archive/` (via `git mv`, history
  preserved). `docs/archive/README.md` records what each was and that several
  of their claims were checked and found false.
- `TASKS.md` is now a pointer to this plan.
- `configs/opencode/skills/task-board` and `task-execute` updated to name
  `docs/NOXFLOW_REPAIR_PLAN.md` and to warn off `docs/archive/`.
  `codebase-tour`'s example described a *different, retired* project
  (`apps/api`, `runtime/ai.db`, `pnpm`) and pointed at `PLAN.md`; it now
  describes this repository.
- `legacy/` archived: it held one README saying "do not move Wayle yet", a
  decision that has been made — `wayle/` stays as the documented fallback.
- `~/.local/bin/noxctl` was a 3.4 MB **copy** of `target/release/noxctl` built
  on a different day. `normalize-links.sh` now symlinks it (and skips, with the
  fix command, when the binary is not built).
- Cleared: `shfmt -i 2 -ci` drift in `check-noxflow-binaries.sh`,
  `theme-sync.sh`, `ai-session.sh`, `release-gate.sh`; missing trailing
  newlines; non-executable `bootstrap-noxflow.sh` and
  `wallpaper-handpicked.sh`.
- `hypr/scripts/shell-diagnostics` grepped for five notification daemons then
  filtered the answer down to four — excluding `quickshell`, the one that
  actually owns them. It always printed `none-detected` on a healthy machine.
- New guard in `check-stale-references.sh`: a superseded plan referenced as
  current guidance fails the check (scope: README, cheatsheet, AGENTS.md,
  `setup/`, `configs/`, `ai/`; archive and dated audit records excluded).

`check-stale-references.sh` and `check-shell.sh` both pass.

### Phase 5 — in progress (2026-10-09)

**Heartbeat and reconnect — done.** `NoxdClient` now sends `ping` every 15 s once
the subscription is live and reconnects after two missed pongs. noxd
silently drops a subscriber whose 256-slot event queue fills, and a half-open
socket previously looked connected forever: the shell kept rendering the last
snapshot and nothing reported the stall. Verified live — pongs round-trip at the
15 s interval with zero false misses.

> Two bugs found while verifying it, both from the same mistake:
> `property int lastPongAt` — **QML's `int` is 32-bit and `Date.now()`
> (~1.79e12) overflows it.** The idle check read ~1.8e9 seconds and tore the
> socket down on the very first tick, reconnecting in a loop. Both `lastPongAt`
> and `SettingsPanel.lastStatusAt` are now `double`.

**GPU polling — fixed, and it was dead in the other direction.** Decision 9's
gate existed (`SystemModel.gpuPollingEnabled`), but `HealthBody.active` was
declared `readonly property bool active: true`. A constant emits no change
signal, so `onActiveChanged` never ran and the discrete GPU was **never**
polled: the health dashboard showed "GPU n/a" forever. It now enables polling in
`Component.onCompleted` — the body's lifetime *is* the dashboard being open —
and clears it on destruction.

**Phase 5 remainder — done (2026-10-09).**

- **Snapshot-replace semantics were wrong.** `publishSnapshots` merged *every*
  snapshot into `snapshotCache`, so a complete `get_state`/`subscribe` reply
  was treated as a delta and any key the provider had **dropped** was
  resurrected from the cache and kept forever — a disconnected SSID came back, a
  list a provider had emptied stayed populated. Complete snapshots now replace;
  only event frames merge. The cache is also reassigned rather than mutated in
  place, so readers see a new map instead of a stale one.
- **Event frames invented health.** `handleEvent` built
  `{ status: "available", data: ... }` for every event, even though
  `EventEnvelope` (`core/noxflow-ipc/src/lib.rs`) has no status field, so a
  provider the daemon had marked `error` flipped back to green on every event it
  emitted. Events now keep the provider's known status; a provider never heard
  of counts as available because receiving data is that evidence.
- **`subscribe` was retried on the same connection.** `canRetry` only blocked
  human/device handshakes, so a timed-out `subscribe` was re-sent in place — the
  daemon registers a second subscription and the shell receives every event
  twice. `subscribe` is now never retried; the failure path drops the socket
  and the normal reconnect subscribes exactly once.
- **WeatherModel:** `ensureCacheDir` was declared and never invoked, so a fresh
  machine with no `~/.local/state/noxflow` never read or wrote its cache; it now
  runs at `start()` and the cache path is set even if `mkdir` fails. Retries are
  exponential (1 min doubling to a 30 min cap) instead of a flat 60 s forever,
  and only the first two failures are journalled — an outage no longer writes a
  line a minute indefinitely. Recovery is always logged.
- **`qt.svg.draw: buffer too big` — NOT resolved. This entry previously
  claimed it was resolved; that was wrong, and the claim is corrected here.**
  It does not occur at boot, which is what the earlier note measured and then
  over-generalised: `Launcher.qml` gates its app icons on `openProgress > 0.5`,
  so nothing rasterises at startup. **Open the launcher and it reproduces**,
  measured at 12–27 occurrences for a single open depending on how many results
  the list holds, and 53 across a full smoke run that opens it repeatedly. Re-measured 2026-10-09 after a verifier flagged the false claim.

  What was ruled out, each by experiment:

  - *Unbounded `sourceSize`* — no. `Quickshell/Widgets/IconImage.qml` already
    sets `sourceSize` to `actualSize` (`min(width, height)`), so the target is
    already the 28px tile.
  - *Target size* — no. Replacing `IconImage` with a plain `Image` at a literal
    `sourceSize` of 8, 28 and 128 px gave an identical warning count at all
    three sizes.
  - *The SVG files* — no. In an offscreen `qml6` harness, each of the 13 loaded
    app icons, individually and all together, renders at 28 px with **0**
    warnings.
  - *The `image://icon/` provider* — almost certainly where it comes from. In
    the shell the only icon that produced no warning was the one loaded from an
    absolute `file://` path (`studio.svg`); every `image://icon/…` one warned.

  It is emitted by Qt's SVG rasteriser (`qt.svg.draw`, Qt 6.12) and is
  **non-fatal** — screenshotting the open launcher shows every app icon
  rendered correctly. No code change was kept: the attempted replacement
  changed nothing measurable, so `Launcher.qml` still uses `IconImage`. A real
  fix means resolving theme icons to real filesystem paths instead of
  `image://icon/…`, which needs a small icon-theme lookup the shell does not
  have yet. Left open rather than papered over.

Extracted `SnapshotMerge.js` and added `test_snapshot_merge.js` (suite total
now 18) so the merge rules are unit-testable rather than buried in a QML
function.

**Still open in Phase 5:** the CPU temperature fix was the last item still
listed as required and not yet implemented — it is now done and is described
under Phase 4 below, together with a regression the Phase 4 work introduced and
then caught. Nothing from this section's list remains open.

### Phase 5 — notifications: dunst retired, Quickshell owns the bus (2026-10-09)

`dunst.service` is **masked** (`systemctl --user mask dunst.service`, no dunst
process). Quickshell owns `org.freedesktop.Notifications`. Restore with
`systemctl --user unmask dunst.service`.

`NotificationBridge.qml` is the shell's ingress: `NotificationServer` is
*instantiated* (a bare singleton reference never claims the bus), arrivals come
from its one signal `notification(Notification)`, and `NotificationModel` is a
plain shell-side store that also holds DND.

Getting the badge to actually count took four separate bugs, none of which
produced an error the load check could see:

1. **`shell.qml` declared `NotificationModel { id: notificationModel }` and then
   wrote `notificationModel: notificationModel`.** QML resolves a property ahead
   of an id, so the right-hand side bound to TopChrome's own property and
   TopChrome received `undefined`. The bar's badge therefore read
   `undefined.length` and was structurally incapable of ever showing a count.
   The id is now `notifStore`.
2. **`trackedNotifications` is unusable.** It is a QAbstractItemModel whose
   `rowCount()` stays **0 while a notification is live**. A Repeater wired to it
   produces zero delegates, silently, forever.
3. **`Notification.closed` is never emitted.** Because the server does not track
   what it hands to QML, a 2000 ms `expire_timeout` notification was still live
   ten seconds later and a sender-initiated `CloseNotification` produced nothing.
   Expiry is therefore owned by the shell: a 1 s sweep retires whatever has
   outlived its timeout and calls `dismiss()` so the sender is still told.
   *Documented limitation:* a sender closing its own notification behind the
   shell's back stays visible until its timeout.
4. **`NotificationItem` used Quickshell's `FrameAnimation`, which 0.3.2 does not
   export at all**, so the card could not be instantiated and the centre drew
   its header and "Active (2)" over an empty body. Its `implicitHeight` also
   read `layout.height` on an `anchors.fill: parent` child — a circular binding
   that measured 0 and stacked every card on one point.

The same shadowing bug was live in two more places and is now fixed:
`aiClient: aiClient` gave **Launcher and Capture a null AI client**, so every AI
action in the launcher and in Capture's panel was dead (decision 3 was not
actually working). The id is now `aiClientInstance`. Note that qualifying the
reference does *not* fix this — an id is not reachable as `shellRoot.aiClient`.

`test_action_routing.sh` was asserting the weaker old contract
(`notifModel.dismissNotification`); it now requires `bridge.dismiss` and forbids
the model-only path.

**Verified live:** badge counts up and down, auto-expiry clears it and reverts
the glyph, and the notification centre renders real cards with app name, summary
and body.

**Still open:** the control centre's DND tile and the notification centre's
dismiss/Clear are now wired to the model and bridge respectively, but neither
was exercised by a real click — only by inspection.

### Phase 4 — panels and ControlCentre (2026-10-09)

**Two coordinators merged into one.** `SurfaceCoordinator.qml` is deleted.
`PanelController` now owns the modal stack and Escape routing. They could not
see each other, which is how the rules came to contradict themselves:
PanelController closed every other panel when one opened, while
SurfaceCoordinator's own contract said panels "may coexist with each other and
with modals", and Escape followed whichever list it was handed. The modal stack
and Escape decision are extracted to `core/SurfaceStack.js` and covered by
`test_surface_stack.js`.

Escape could not be verified by keystroke on this machine — no key-injection
tool is installed and Hyprland's lua dispatch rejects `sendshortcap` — so the
routing is pinned down as a unit test against the module the controller calls.
**The one-panel-at-a-time rule *was* verified on screen**: opening the
notification centre and then the calendar leaves only the calendar visible.

The dead `Opening`/`Switching`/`Closing` states, `isAnimating` and `visualState`
are removed. All were assigned and overwritten inside one synchronous call, so
nothing could read them; the real transition belongs to MorphSurface, which
reports back through `panelClosed()`.

**ControlCentre: 1531 lines -> 193.** Split into `ControlCentre.qml` (host),
`ControlCentreState.qml` (view state), `WifiConnectFlow.qml`,
`ControlTabBar.qml`, `tabs/{Quick,Audio,Network,Bluetooth,System,Input,Power}Tab.qml`
and `tabs/QuickBluetooth.qml`. Every file is under 350. The extracted tabs reach the host through a single
`host` property rather than a dozen forwarded properties.

**Three defects found while splitting, all predating it:**

1. `ControlTile` set `height: 68`, but every tile sits directly in a
   `ColumnLayout`, and a layout assigns `height` to its children — overwriting a
   manual height with `implicitHeight`, which for a bare `Rectangle` is 0. The
   tile collapsed, the `RowLayout` had no room, and the label, subtitle and icon
   were painted on top of each other with no card background visible. It is
   `implicitHeight` plus `Layout.fillWidth` now.
2. The tile's icon `Text` set no `font.family`, so it rendered in the app
   monospace face, which has none of the Nerd Font private-use codepoints every
   icon in this shell is written in. Icons came out blank with no error.
3. The tile icons were raw geometric characters (`U+2301`, `U+25C8`, `U+2298`,
   `U+25C9`) that are not in the icon font either, and the wifi tile's ternary
   had identical branches. All now use the codepoints the capsules already use
   (`U+F1EB` wifi, `U+F294` bluetooth, `U+F0F3` bell, `U+F056` minus-circle,
   `U+F025` speaker, `U+F026`/`U+F028` mute/volume).

**A missed import caught only by the journal, not the load check:**
`ControlCentreState.qml` used `Utils.asArray` without importing `ModelUtils.js`.
That is a runtime `ReferenceError` inside a function, so the config still loaded
"cleanly" and the load gate passed — the empty Wi-Fi list and Bluetooth count
only showed up as two journal warnings. **Worth remembering: a clean load is not
a clean shell.**

**One geometry table.** `MorphSurface.qml` defined panel sizes three times and
they had drifted: `targetHeight` sized the launcher at 520 while
`targetGeometryFor()` let it fall through to the 720 default, and only the
latter knew about `sync` and `quick-share`. Every size now comes from one
`panelSize(name)` function that `targetSize`/`targetWidth`/`targetHeight`/
`targetGeometryFor` all read. **Verified on screen:** the control centre's layer
surface measures 640 px tall and the calendar's 650 — exactly the table's
values — and both layers disappear entirely on close.

**Two dead things in the close path, found while reading it.** `retainWindow`
was written twice and read never, so the comment claiming it held the window
open described behaviour that did not exist; the retention was real but
incidental (nothing assigns `surfaceHeight` on that branch). Worse,
`collapseTimer.interval` was *mutated* on the no-origin close and never
restored, so the first origin-free close left every later close using
`contentExit` (95 ms) instead of the morph duration (205 ms) — the layer
shrinking while the frame was still collapsing. Both removed; each close now
sets its interval from a readonly property.

**Keyboard focus — the plan's prescription was necessary but not sufficient.**
All five panel windows (`MorphSurface`, `Capture`, `RadialWheel`, `Dashboard`,
`SettingsPanel`) now request the seat explicitly with
`WlrLayershell.keyboardFocus` instead of the permissive `focusable: true`.
Measurement, however, shows that alone does **not** hand a panel keyboard
input. A panel's `FocusScope` reports `focus: true` and `interactive: true`, yet
`activeFocus` is `false` and `window.activeFocusItem` is `QQuickRootItem` — the
state in which `Keys.onEscapePressed` never runs. `forceActiveFocus()` after the
Loader mounts the panel moves the active focus item off the root and into the
panel tree, so that is called on load and on panel switch.

**Escape still needs a human to press it.** Hyprland 0.56's lua API does expose
`hl.dsp.send_shortcut({ mods = 0, key = … })`, but it reports success and
delivers nothing: injecting into a focused kitty window produced no character.
There is no click dispatcher either (`hl.dsp.cursor` has only `move` and
`move_to_corner`), so no pointer-driven check is possible from the shell. What
*is* measured is the Qt-side focus promotion; end-to-end key delivery is not.
`TextField` also had `Keys.onEscapePressed: root.focus = false` without accepting
the event, so the press propagated to the panel and closed it in one keystroke —
making that line a no-op. It accepts now, giving the intended blur-then-close.

**Token-sized controls.** `Toggle.qml` hardcoded 52x32 with a 22 px knob and
x positions of 5/27, and `Slider.qml` hardcoded 4/20/240; neither could follow a
density change. New `Tokens.heightSwitchTrack`, `widthSwitchTrack`,
`sizeSwitchKnob`, `heightSliderTrack`, `sizeSliderKnob`, and both components now
derive every dimension from tokens.

**Nine inline progress bars replaced**, not the three the plan listed: dashboard
CPU/GPU/RAM, control centre SystemTab CPU/RAM/GPU/Disk and the PowerTab battery,
the QuickShare transfer row, and the island activity bar. `Slider.qml` gained a
`readOnly` mode for the eight indicators — `enabled: false` is not usable there
because it also applies the disabled opacity to a bar that is still meaningful.

**A latent binding bug in `Slider.qml`.** It assigned its own `value`, which
destroys the caller's binding — the same defect class as MorphSurface. After a
brightness drag the bar would have stopped tracking the model entirely. It now
follows the `Toggle.qml` contract: never assign the bound property, and paint a
local `dragging`/`dragValue` pair during a drag so the bar still tracks the
pointer while QuickTab's debounced commit is in flight.

**`components/SettingRow.qml`** factors out the label / current-value / control
row that was hand-written all over `SettingsPanel.qml`; the control is the
default property. Three rows converted (density, reduced motion, corner radius).

**`components/Command.qml` — all 37 inline `Process` objects are gone.** The
single remaining `Process` in the tree is the one inside the runner. Every one
of them assigned `command` then set `running`, kept its own buffer, and often
discarded the exit code. The runner always captures stdout and stderr, always
reports the exit code through `exited()`, clears the previous argv before
starting, and refuses to start a second run. Three silent-failure patterns went
with it:

* `UpdateModel` ran `status-updates.sh 2>/dev/null || printf '{"count":0,…}'`,
  so a broken script was indistinguishable from an up-to-date machine. It now
  records the failure and leaves `lastError` set.
* `WallpaperModel` read the current wallpaper with `cat … 2>/dev/null || true`,
  making a missing cache file look like "no wallpaper set".
* `Capture`'s save path carried its own `notify-send 'Screenshot failed' 'grim
  returned an error'` inside the shell string — a second, always-identical
  failure message — while the sibling Lens path reported the real exit code.
  Both now report through one path.

`SettingsPanel` also gained the plan's "restart daemon keeps the panel open until
the result banner shows": the close moved out of the click handler into the exit
handler, behind a `closeAfterMaintenance` flag.

**Wi-Fi connect flow moved into `NetworkModel`** (44 -> 250 lines;
`ControlCentreState` 272 -> 178). The flow had to be resolved by the host
watching `connectedSsid` and poking it by hand, because the only component that
could act on a network change could not see the attempt. The model now owns the
whole state machine and calls `onConnectedSsidChanged()` from `applySnapshot`,
where the data actually changes; `ControlCentreState` keeps the same property
names as aliases so no call site changed. Transient status is a `wifiStatus`
signal rather than a field the model writes — `statusChanged` was tried first and
collides with the change-signal of `ProviderModel.status`.

**CPU temperature now comes from the CPU's own sensor.** It was the maximum
over every `thermal_zone*/temp`, which on this machine also spans the WiFi radio
(57 C), ACPI and DIMM sensors — so the number labelled "CPU" was frequently not
the CPU. It reads `coretemp`/`k10temp` `temp1_input` (the package sensor) first,
falls back to the `x86_pkg_temp` zone, and only then to the old max scan.
**Measured:** the shell now reports the coretemp package value where the old
method reported a lower number from a different zone.

**Two regressions this phase introduced, both caught before delivery:**

1. Migrating `SystemModel` to `Command.qml` tested the `snapshotApplied` flag
   *before* calling `applySnapshot()` — which is the call that sets it. Every
   poll therefore looked like an empty snapshot and the dashboard sat at
   "Telemetry unavailable". Caught on screen, not by the load gate or the tests.
2. `Slider.qml` used the 44px interactive touch height as its `implicitHeight`
   in every mode. In the dashboard's fixed-height tiles a read-only bar claimed
   44px and pushed the CPU temperature line out of the tile entirely — the same
   `ControlTile` layout trap as the tile collapse above, in a new place.
   Read-only bars now size to their track.

**`QuickTab.qml` 358 -> 203 lines.** It had outgrown the "every control-centre
file stays under 350" rule. The Bluetooth section — adapter toggle, discovery,
device list, pairing prompt, audio hand-off — was one 160-line inline block and
is now `tabs/QuickBluetooth.qml`, reached through the same single `host`
property. While moving it, a second mangled accessibility label of the same
kind as `"Screen host.brightness"` turned up: `"Bluetooth host.power"`; both are
now real names, and the shell is swept for the pattern.

**Phase 7 leftover fixed.** `setup/project-profile.sh` still sourced
`hypr/scripts/workbench-runtime-env.sh`, deleted in 8022f56 ("retire local
workbench and model runtime"), so under `set -euo pipefail` the script — and
`setup/test-project-profile.sh` — died at line 1. Three other live scripts
(`kage`, `kage-project-rofi.sh`, `project-resume.sh`) sourced the same removed
file and were equally dead. The four now share `hypr/scripts/lib/workbench-env.sh`,
which keeps the behaviour they were written against (user-owned `runtime.env`
if present, then the same defaults) instead of deleting working entry points.
`test-project-profile.sh` passes again.

**Escape: the Qt side is now measured, the keystroke is not.** After the
keyboard-seat change, a panel's `FocusScope` reports `interactive: true` and
`focus: true` **and now `activeFocus: true`**, with `window.activeFocusItem`
being a `QQuickFocusScope` rather than `QQuickRootItem` — i.e. key events now
route into the panel instead of dying at the scene root, on open and with no
click. That is the state `Keys.onEscapePressed` requires.

What is still not measured is whether the compositor then delivers the physical
keystroke. Three injection paths were tried and all failed: Hyprland's
`hl.dsp.send_shortcut` (reports success, delivers nothing), `hl.dsp.send_key_state`
with `state = "down"/"up"` (same), and `hl.dsp.window.close`/focus dispatch
(which do not even change focus, so no positive control could be set up). No
key-injection tool is installed, and installing one is a system change that has
not been authorised. **So: Escape needs a human pressing it once.**

**Still open in Phase 4:** none of the listed items remain. Unverified and not
claimed: Escape by keystroke (above), and the System/Power control-centre tab
bars, which are conversion-identical to the three dashboard bars that were
checked on screen.

### Phase 1 re-verification — the OSDs were dead (2026-10-09)

Systematically re-checking Phase 1's 14 items, 13 confirmed mechanically. The
fourteenth — 1.10, the "island stall" — could not be reproduced, because there
was nothing to stall: **no OSD had ever displayed.** Volume, brightness and
media OSDs were all dead, panel open or closed. The plan had blamed
`display()` returning early for `panelOpen`, and that early return does exist
and does defer correctly — it was simply never reached.

Three independent defects, each sufficient on its own, found by instrumenting
the chain rather than by reading it:

1. **The daemon event stole the guard.** `IslandEvents.onEventReceived` kept
   `guardVolume`/`guardBrightness` in step "so the model path does not fire a
   duplicate". noxd publishes the event and the model snapshot from the same
   wake-up, so the event always landed first, set the guard to the new value,
   and the model handler then bailed out on its own
   `abs(new - guard) <= 1` test. Volume and brightness OSDs could therefore
   never fire. The `e.provider === "audio" && e.data` condition also let an
   audio event with no payload fall through to the media/power branches.
   *Probed:* `PROBE volume: 55 guard: 55` — the guard was already the new value
   when the model handler ran.
2. **Both split components were wired backwards.** `IslandQueue` and
   `IslandEngagement` *assign* the properties the island renders from, but
   `IslandQueueHost` and `IslandHost` bound those same properties *down* to
   them. Every write landed on a bound property and was swallowed.
   *Probed:* immediately after `queue.show()`, the host still reported
   `currentKind="idle"`, `activityLabel=""`, `expanded=false`, `osd=false`.
   Fixed by direction: only properties a component reads are bound to it, and
   written properties are pushed up through `on<Property>Changed` handlers.
3. **The split dropped `islandState = entry.kind`.** The pre-split
   `NoxIsland.display()` assigned it; when `display()` moved into `IslandQueue`,
   which owns only its own mirrors, nothing set `islandState` on the OSD path.
   The card paints from `islandState`, not from the engagement machine — a
   routine OSD is a deliberately *non-expanded* pill with an icon and a slim bar.
   Set in `IslandEngagement.onActivityReady` now.

Fixing (3) surfaced a load-gate failure that was itself instructive:
`Binding loop detected for property "onSettled"`. `onSettled` was a *bound*
property, so every property its body read became a binding dependency — and the
callback re-seeds the OSD guards, which the body also reads. The binding was
writing its own dependency. It is a `settled` signal now; a signal has no
dependency tracking, which is what a callback that deliberately mutates host
state needs to be.

**Measured after the fix** (`grim` + diff against an idle frame):

- volume 45% → OSD pill paints with speaker icon, "Volume" and a filled bar;
- with the Control Centre open, the volume activity is deferred
  (`queue.panelOpen=true`) and replayed the moment the panel closes;
- brightness 55% → OSD paints with sun icon and "Brightness".

**Regressions this would not have caught.** All 19 suites and the load gate
passed while every OSD was dead: none of these are parse-time or structural, and
`qmllint` cannot resolve the Quickshell imports at all. `test_island_contract.sh`
now asserts the wiring direction (a bound-down property the component also
writes is a failure), the `islandState` assignment, and the single-producer rule
for the OSD guards; the direction check was verified to fail when the bug is
reintroduced. Two assertions in that file were also passing *vacuously* — they
ran `grep` on a directory, which exits non-zero with "Is a directory" and whose
failure the surrounding `!` turned into a pass. Now `grep -r`.

Audio and brightness were restored to their pre-test values (40% / 100%).

#### The same audit found three more split casualties, all invisible

Looking for the bound-down pattern elsewhere turned up the rest of the damage,
all in the island and all from the Phase 3 split:

4. **`IslandLayers` was bound down too.** It assigns `calendarExpanded`,
   `launcherOpen`, `launcherClosing` and `launcherWasVisible`, and `IslandHost`
   bound all four *down* to it — so the writes stopped at the layer.
   `launcherVisible` therefore never went true, taking with it
   `TopChrome`'s `keyboardFocus: island.launcherVisible`, the launcher's width
   and Escape rule, and `shell.qml`'s `if (host.launcherVisible) closeLauncher()`.
   Now pushed up, the same way as the queue and the engagement machine.
5. **`IslandHost.implicitHeight` was dropped entirely**, leaving the
   `Behavior on implicitHeight` below it animating a property nobody assigned.
   `TopChrome` sizes its window to `max(heightToolbar, island.implicitHeight)`,
   so the island's window stayed **44px** — the height of the bar — and every
   surface below the bar was clipped. This is why the bugs above stayed
   invisible: the idle pill draws inside that strip and looks plausible.
   Restored, including the dashboard and idle branches.
6. **The calendar's `open()`/`close()` calls were dropped.** `CalendarWidget`
   runs its own `SurfaceLifecycle`: its body is `opacity: openProgress` and it is
   `visible: lifecycle.active`, both zero until something calls `open()`. The
   container was visible and correctly measured at 520x650 while the widget
   inside it stayed invisible and fully transparent. *Probed:* before the fix,
   `calExpanded=true hostItem={700,0,520,650} visible=true` and nothing on screen.

**Measured after all six fixes** (`grim`, and a probe driving the same functions
the pointer would):

- volume OSD paints with speaker icon, "Volume", the percentage and a filled bar;
- brightness OSD paints with the sun icon and "Brightness";
- an activity raised while the Control Centre is open is deferred
  (`queue.panelOpen=true`) and replayed the instant the panel closes;
- the inline calendar opens and paints a full month grid with navigation;
- the launcher loads and paints its search field and tabs;
- the idle pill is a properly rounded, correctly sized pill.

`test_island_contract.sh` covers 4, 5 and 6 too, and each assertion was verified
to fail when its defect is reintroduced.

### Measured against this plan's own acceptance criteria (2026-10-09)

Two criteria in this document were not met at one point. One is now met; the
other is recorded rather than quietly reinterpreted.

**1. Phase 2's line-count target is unmet.** Its acceptance required QML code to
*drop* by ≥1,500 lines. Measured with the same `tokei` build against the
pre-repair tree, pinned to `095e7fd` — the commit before this work landed.
It is named rather than written as `HEAD~1`, because `HEAD~1` moves as soon as
anything else is committed: `setup/check-noxflow-plan.sh` caught exactly that,
reading the repair commit back as the baseline the moment a second commit
landed.

| | files | raw | code |
| --- | --- | --- | --- |
| pre-repair (`095e7fd`) | 81 | 13,944 | 11,742 |
| *superseded*: before the split of `IslandHost` and the dead-file removal | 117 | 16,792 | 12,876 |
| now (committed) | **111** | **16,664** | **12,770** |

Whole `shell/noxflow` code: 14,191 → 16,131.

The dead code *was* removed and the two oversized files *were* split, but the
split added 36 files of imports, property wiring and headers, and that cost
more than the deletions saved. Removing the dead files that remain moved it
only 12,876 → 12,770. Seven genuinely unreferenced components were found and
deleted (six in `components/`, plus the `Metrics` singleton and its `qmldir`
registration), each confirmed unreferenced by a namespace-aware search rather
than a plain filename match — the first two attempts at that check produced 80
and then 47 false positives, because QML uses `Local.Foo` and not `Foo.qml`.

So the gap is structural, not a missed cleanup. Meeting −1,500 against `HEAD`
now means cutting a further **~2,530 QML code lines — about 20% of the shell's
QML code** — from a shell that passes every gate. That is a decision about
which features to remove, not a refactor, and it is not this plan's to take
unilaterally. Recorded, and not claimed as met.

**2. `island/IslandHost.qml` over the 350-line cap — RESOLVED.** It reached
382 lines during the Phase 1 re-verification (the plan had recorded a stale
371), because putting back `implicitHeight`, the calendar `open()`/`close()`
calls and the `islandState` assignment — plus the wiring-direction fixes — all
belong in the host.

It is now **350**. `island/IslandProducers.qml` hosts `IslandEvents` and
`IslandTimers`, which were previously instantiated inline. That seam was chosen
precisely because it is the safe kind: both components already coupled to the
host by *callback* (`enqueue`, `deactivate`, `clearDashboardStatus`), so hosting
them together introduces no new mirrored property. The two values the host does
read, `timerRemainingSeconds` and `timerActive`, flow child -> host. Three
sibling boundaries in this directory were wired backwards this session and each
silently disabled the island, so no new state boundary was added casually.

Verified after the split, not just loaded: load gate clean, 19/19 suites, 23/23
smoke, no `ReferenceError`/`TypeError`/`is not a function` in the journal of the
instance the smoke ran against, and the volume OSD re-measured on screen at 50%
with icon, label and bar — that path runs through the moved producer.

Both numbers above are re-measurable — and are now *asserted* by
`setup/check-noxflow-plan.sh`, which runs in `setup/release-gate.sh`. It
compares this table and the recorded file sizes against `tokei` and `wc`, fails
if the header overclaims, and fails if the phase gate regresses to
`journalctl -b`. Each assertion was negative-tested by corrupting the plan and
confirming the check fails.

That guard exists because of a specific failure: while correcting the table in
0.5, the Phase 2 acceptance block below kept quoting the superseded figures
(12,876 / 16,792 / 117 files). Both had been true when written, only one was
true when read, and the stale copy is the one a reader lands on. Numbers in a
status document need a checker, not good intentions.

---
---

## 1. Decisions (made — do not re-litigate)

1. **Refactor NoxFlow; do not rewrite it.** The daemon, IPC handshake,
   subscriptions and frame validation are sound. A live probe shows `noxd`
   accepts every action the shell sends except `ai_query`. The breakage is in
   the QML glue: dead paths, missing binaries, duplicated state. Fix in place,
   phase by phase, and keep the shell runnable after each phase.
2. **One plan, one ledger.** This file is the plan.
   `docs/NOXFLOW_BUGS_UX_COMPLETION_PLAN.md` stays as the historical ledger.
   - Move `PLAN.md`, `PLAN_v2.md`, `theplan.md` and `OPENCODE_TASK.md` to
     `docs/archive/`.
   - Delete `session-ses_05bd.md` (338 KB transcript; git history keeps it)
     and `zshrc.bak.20260710-105151`.
   - Replace `TASKS.md` with a pointer to this file, and update
     `configs/opencode/skills/task-board` and `task-execute` in the same
     commit.
3. **No external app is hardcoded in a view.** Add one `config/Apps.qml`
   singleton:
   - terminal = `kitty`, files = `dolphin`
   - "Settings" opens NoxFlow's own SettingsPanel, not
     `gnome-control-center`
   - file picker = Qt `FileDialog`, not `zenity`
   - OCR = `grim | tesseract` directly, with no `magick`

   Each command is checked once at startup. A missing binary disables the
   entry with a tooltip; it never fails silently.
4. **One AI path.** A shared `services/AiClient.qml` reads `ai.endpoint`,
   `ai.model` and `ai.provider` from noxd settings (they already exist in
   `settings.rs`). Launcher and Capture both use it. Drop the `ai_query`
   daemon action from Capture.
5. **Notifications: Quickshell owns them.** Use
   `Quickshell.Services.Notifications.NotificationServer` and retire dunst.
   The current NotificationModel is fed only by the unloaded `Gallery.qml`, so
   the bar pill and island render fake data. DND becomes one property on one
   model; the three disagreeing write paths are removed.
6. **Bar layout (final).**
   - Left: workspaces and the health capsule.
   - Centre: the island, which keeps the clock (no second clock).
   - Right: system tray (new, `Quickshell.Services.SystemTray`), connectivity,
     audio/power, mic-in-use indicator (new), notifications, updates.
   - Remove the sync pill (hard `visible: false`, no backing provider) and the
     duplicate left update slot.
7. **Island scope = what has a producer.** Delete
   `showNotification/FileTransfer/AiCompletion/BuildResult/BatteryWarning/NetworkWarning`,
   the "updater" phantom route, and the unreachable
   network/battery/clock/mic branches. Re-add a kind only together with its
   producer, through one `IslandRoutes.js` table.
8. **One surface registry.** Merge `SurfaceCoordinator` into
   `PanelController`. Every modal (dashboard, settings, capture, radial)
   opens through it, so at most one is open at a time. Escape closes the
   active surface on the focused monitor only.
9. **Event-driven, not polled.**
   - Remove the 250 ms Bar timer; register morph geometry on change signals.
   - Workspace switching goes through noxd `WorkspaceFocus` instead of
     `hyprctl eval`.
   - Keep the 1 Hz clock timer, but only for the clock.
   - Replace the 2 s `nvidia-smi` fork in SystemModel with a 10 s poll that
     runs only while the dashboard is visible, so the hybrid dGPU can sleep.
10. **Styling only through Tokens.** Add `Tokens.iconFont` (replacing the
    "Symbols Nerd Font Mono" literal used in 14 places) and replace the raw
    pixel and duration literals. Read reduced motion from settings in
    `ShellConfig`/`Tokens`; don't hardcode `false`.
11. **Tests gate the shell.** `setup/release-gate.sh` runs all 9 JS suites,
    all 5 contract scripts, a new external-binary check, and a new
    action-payload contract test. Today it runs only `test_protocol.js`.

---

## 2. Phases

Each phase ends with the **gate**:

```sh
node shell/noxflow/tests/run-all.js   # added in phase 1
systemctl --user restart noxflow-shell.service
# Count warnings for the NEW instance only. `-b` is whole-boot and accumulates
# one line per restart, so it is useless as a per-restart gate — it reads 907
# today purely because the shell has been restarted ~30 times today. Scope it
# to the new instance instead:
since="$(systemctl --user show noxflow-shell.service -p ActiveEnterTimestamp --value)"
journalctl --user -u noxflow-shell.service --since "$since" --no-pager -o cat \
  | grep -E 'WARN|ERROR'          # expect 1 on an untouched shell; see below
tests/smoke/test-noxflow-surfaces.sh
```

Measured 2026-10-09: a freshly restarted instance that has not been touched
emits **exactly 1** warning — the documented first-run clipboard read, which
`setup/check-noxflow-load.sh` allow-lists.

The `-b` form makes this look far worse than it is, because it accumulates
across every instance since boot. Counting per instance PID instead makes the
cause obvious — the count tracks what the instance *did*, not when it started:

| warnings in one instance | how many instances today |
| --- | --- |
| 1 | 12 |
| 2–7 | 69 |
| 8–31 | 20 |
| 82–90 | 4 |

The four high instances are the ones the smoke test ran against. Decomposed,
one of them (PID 1068693, 90 total) is 53 `qt.svg.draw` + 36 text-input
teardowns + 1 clipboard read, and it started at 23:06:23 — immediately after
`check-noxflow-load.sh`, i.e. the restart that the smoke test then reused. So
"~89 per instance" is an instance that opened the launcher and cycled panels,
not a fresh one.

This gate only describes an *idle* instance. Once the shell is used, two more
classes appear and are not regressions:

- `qt.svg.draw: buffer too big` — one per app icon the launcher rasterises, so
  a smoke run that opens the launcher shows 12–53. Described in 0.5; still open.
- `qt.qpa.wayland.textinput` "Trying to disable … but 0x0 is focused" — Qt
  tearing down text-input surfaces when panels close. Non-fatal, one group per
  panel close; the 2–7 bucket above is mostly this alone.

So the per-instance count to assert is "1 on an untouched shell", not "0".

### Phase 1 — Stop the visible breakage (small, high value)

| # | Fix | File | Acceptance |
| --- | --- | --- | --- |
| 1.1 | Dashboard "Reload shell": `reload` → `restart` (the unit has no ExecReload, *probed*) | `surfaces/dashboard/Dashboard.qml:556` | Button restarts the shell |
| 1.2 | Settings button / launcher "Settings" → open NoxFlow SettingsPanel | `Dashboard.qml:570`, `Launcher.qml:272` | No `gnome-control-center` reference |
| 1.3 | Radial "Files" → `dolphin` via Apps.qml | `surfaces/radialmenu/RadialWheel.qml:28` | Opens a file manager |
| 1.4 | `Quickshell.exec` does not exist in 0.3.1 → `Quickshell.execDetached` | `Fallbacks.js:32,36`, `RadialWheel.qml:131`, `Capture.qml:640` | `rg 'Quickshell\.exec\('` returns nothing |
| 1.5 | DND read `dunstctl get-paused` (invalid, *probed*) → `is-paused` (later replaced by decision 5) | `ControlCentre.qml:409,774` | Toggle reflects real state |
| 1.6 | Quick Share picker: `zenity` (missing) → Qt `FileDialog` | `surfaces/share/QuickShareContent.qml:66` | Picker opens; an error is shown on failure |
| 1.7 | OCR: drop `magick` (missing) and pipe grim → tesseract | `surfaces/capture/Capture.qml:529,544` | OCR copies text; the error names the real binary |
| 1.8 | Capture AI → AiClient (decision 4) | `Capture.qml:643` | No `ai_query` sent (it currently gets `invalid_request`, *probed*) |
| 1.9 | Update pill tooltip: add `property bool hovered: ho` | `Bar.qml:446,517` | Tooltip shows |
| 1.10 | OSD never displayed. Three defects, not the deferral this row originally blamed — see 0.5 | `island/IslandQueueHost.qml`, `island/IslandEvents.qml`, `island/IslandEngagement.qml` | *Measured:* volume OSD paints 45% with icon/label/bar; deferred while a panel is open and replayed on close; brightness OSD follows |
| 1.11 | Timer tick only writes the label when `currentKind === "timer"`; clear `timerActive` on finish/preempt | `NoxIsland.qml:676` | The timer never overwrites another OSD |
| 1.12 | Persisted appearance applied at boot, not only when Settings opens | `SettingsPanel.qml:216-235` → move to a startup hook in `shell.qml` | A theme set, then a restart, keeps the theme |
| 1.13 | Add `tests/run-all.js` and wire all suites into `release-gate.sh` | `shell/noxflow/tests`, `setup/release-gate.sh` | Gate runs 9 JS + 5 contract tests |
| 1.14 | Fix the smoke error gate matching `QDBusError` | `tests/smoke/test-noxflow-surfaces.sh:89` | Benign portal warning doesn't fail the gate |

### Phase 2 — Delete dead code and duplication (makes phase 3 cheap)

- Remove `Gallery.qml`, `MorphingSurface.qml`, `StateLayer.qml`,
  `MorphRegistry.registerChip`, the dead MorphSurface launcher branches, the
  unused activity components in `surfaces/island/qmldir` (or use them in
  phase 3), `OSD_KINDS`, and the unreachable branches and dead island API from
  decision 7.
- Remove the sync pill and the left update slot (decision 6).
- Use one update launcher (Bar's state machine), so the island's copy is
  removed.
- Use one volume/brightness OSD path: model signals only; drop the duplicate
  noxd-event enqueue. Fix the hardcoded max 100 (`NoxIsland.qml:602`).
- Use one host registry (`shell.qml` `islandHosts`) and one grace timer (in
  ActivityController), with constants from Tokens only (transit 450, dwell
  140).
- Merge `BatteryModel.qml` into `PowerModel.qml`. Drop the calendar and
  clipboard snapshot routing that has no provider (`shell.qml:110-111`), and
  `notifications` from `Protocol.js:27`.
- Bound `ActivityController.lastEventKeys`.
- Acceptance: `tokei shell/noxflow` QML drops by at least 1,500 lines, the
  gate is green, and there are no new journal warnings.
  **NOT MET, and this plan no longer claims it was.** Measured against the
  pre-repair tree (`git archive HEAD~1 shell/noxflow | tokei`), QML **code**
  lines went 11,742 → **12,770** — up 1,028, not down 1,500. Raw lines 13,944 →
  16,664 and files 81 → 111; whole `shell/noxflow` code 14,191 → 16,131. The
  dead code was removed and the oversized files were split, but the split cost
  more lines in imports, property wiring and file headers than the deletions
  saved, so the raw count is the wrong measure of whether this phase worked.
  See 0.5, which carries the same numbers and the reasoning.

### Phase 3 — Restructure the bar and island

Target layout:

```
shell/noxflow/
  config/Apps.qml                 external commands + availability (decision 3)
  services/AiClient.qml           decision 4
  bar/Bar.qml                     layout only
  bar/BarStatusPill.qml           shared pill chrome: glass, hover, focus, tap, tooltip
  bar/WorkspaceCluster.qml  WorkspacePill.qml  WorkspacePresentation.js
  bar/TrayCapsule.qml             new — SystemTray
  bar/UpdatePill.qml  MicIndicator.qml
  bar/MorphTriggers.qml           geometry-change registration (replaces the 250 ms poll)
  island/IslandHost.qml           view + wiring (was NoxIsland.qml, 1146 lines)
  island/IslandCompact.qml  IslandCard.qml  DashboardRouter.qml  dashboards/*.qml
  island/IslandEvents.qml         audio/brightness/media/notification → submitActivity
  island/IslandRoutes.js          the single kind table: panel, section, priority, critical, osd
  island/HoverEngagement.js  ActivityArbitration.js  ActivityController.qml
```

- Per-source hover: either wire `recordSourceHover(kind, false)` on chip exit
  or drop the map. **Decision: drop it** — island-level hover is enough.
- Fix `isClickAway` receiving `[]` as source bounds (`NoxIsland.qml:563`).
- Fix the null guards in workspace entries (`Bar.qml:171-179`).
- Acceptance: no file in `bar/` or `island/` is over 350 lines, and every
  pill uses `BarStatusPill`.
  **Met.** `IslandHost.qml` reached 382 during the Phase 1 re-verification and
  is now back to **350** via `island/IslandProducers.qml`. Largest files:
  `IslandHost.qml` 350, `IslandCard.qml` 317, `IslandEngagement.qml` 309,
  `Bar.qml` 302.

### Phase 4 — Panels and ControlCentre

- Merge SurfaceCoordinator into PanelController (decision 8). Remove the dead
  `Opening/Switching/isAnimating/visualState` states.
- Use one geometry table for panel sizes. The three disagreeing definitions
  are MorphSurface `:45`, `:47-55` and `:271-278`.
- Fix MorphSurface's imperative overwrites of bound properties (`:310-418`):
  use explicit animation targets, so close timing stays the morph duration.
- Keyboard focus: use `WlrLayershell.keyboardFocus` (as TopChrome does), not
  `focusable: true`. Escape must work without a click first.
- Split ControlCentre (1509 lines):
  - `ControlCentre.qml` — host, ~200 lines
  - `ControlCentreState.qml`
  - `WifiConnectFlow.qml` — state moves into NetworkModel
  - `BluetoothPairing.qml`
  - `ControlTabBar.qml`
  - `tabs/{Network,Audio,System,Input,Power}Tab.qml`
  - `components/SettingRow.qml`
- Replace the inline progress bars with `components/Slider.qml` and make
  `Toggle.qml` token-sized.
- Move about 30 inline `Process` objects behind one `components/Command.qml`
  runner. It reports exit codes to the UI and never `2>/dev/null` +
  `|| echo`.
- "Restart daemon" keeps the panel open until the result banner shows.

### Phase 5 — IPC robustness and models

- Heartbeat: `ping` every 15 s, and reconnect on a missed pong. noxd silently
  drops subscribers whose 256-slot queue fills.
- Never retry `subscribe` on the same connection (it duplicates events).
  Reconnect instead.
- Snapshot merge replaces provider state; it doesn't merge into the stale
  cache. Event frames don't force `status: available`.
- Coalescing: keep `set` and `adjust` in separate slots.
- Decision 5: NotificationServer model + island notification activity;
  remove dunst from autostart and packages.
- SystemModel: read the CPU temperature from the `k10temp`/`coretemp` hwmon,
  not the max over all zones, and apply the decision-9 polling rules.
- WeatherModel: create the cache dir, add exponential backoff, and don't spam
  the journal on curl exit 35.
- `qt.svg.draw: buffer too big` — still open, and the stated cause here was
  wrong. It is not an unbounded `sourceSize` (`IconImage` already bounds it to
  `min(width, height)`) and not the SVG files (they render clean offscreen at
  28 px). It reproduces on **opening the launcher**, 12–27 per open (53 across a
  full smoke run), not at boot. Evidence and what was ruled out are in 0.5. A
  fix means resolving theme icons to real filesystem paths rather than
  Quickshell's `image://icon/…`.

### Phase 6 — Tests that would have caught this

- Action contract test: a Rust test in `core/noxflow-ipc` deserialises every
  action payload produced by the QML. Fixtures come from a script that greps
  `sendAction(`/`runAction(` call sites. It would have caught `ai_query`.
- `setup/check-noxflow-binaries.sh`: every command in `Apps.qml` plus
  `Process` command literals → `command -v`.
- `qmllint` over `shell/noxflow` in the gate (it catches `Quickshell.exec`).
- NoxdClient tests: reconnect, no duplicate subscribe, snapshot replace.

### Phase 7 — Repo hygiene

- Do the doc moves from decision 2.
- `~/.local/bin/noxctl` is a copied 3.4 MB binary; make it a symlink to the
  cargo build output in `normalize-links.sh`, so it can't drift.
- `setup/project-profile.sh` sources the missing
  `hypr/scripts/workbench-runtime-env.sh`. Restore it or remove
  project-profile.
- Pre-existing check failures to clear:
  - shfmt on `setup/ai-session.sh` and `hypr/scripts/theme-sync.sh`
  - the non-executable `setup/bootstrap-noxflow.sh` and
    `setup/wallpaper-handpicked.sh`
  - waybar/swaync references in `docs/shell-repair-*.md` and
    `hypr/scripts/shell-diagnostics`
- `legacy/` and `wayle/`: keep `wayle/` (the documented fallback) and archive
  `legacy/`.

---

## 3. Audit claims that were checked and rejected

- "Unit-variant actions (`lock`, `media_next`, …) sent as `{name:{}}` are
  rejected by noxd." **False** (*probed*): `{"network_refresh":{}}` and
  `"network_refresh"` both return `action_accepted`.
- "`tests/smoke/test-noxflow-surfaces.sh` does not exist." **False**: it is at
  the repo root, `tests/smoke/`.

## 4. Open risks

- Phase 5's switch to NotificationServer required that dunst is not running.
  **Done** — dunst is masked and Quickshell owns the bus. Undo with
  `systemctl --user unmask dunst.service`.
- Quickshell 0.3.2 does not track notifications it hands to QML
  (`trackedNotifications.rowCount()` stays 0) and never emits
  `Notification.closed`, so shell-side expiry is mandatory rather than
  belt-and-braces. If Quickshell is upgraded, re-measure before trusting the
  server to retire anything on its own.
- The MorphSurface `callLater` race and focus/Escape are inferred from source
  and runtime state respectively; each fix must include the repro steps above
  as its acceptance check. **Item 1.10 is no longer in this list** — its repro
  now passes on screen, but it turned out to be three separate defects, none of
  them the deferral this plan originally blamed (see 0.5).
- `setup/client-backup-remote.conf.example` noxorigin entries are unverified
  against the server layout (`/home/apps/noxorigin/{staging,production}/.env`,
  host PostgreSQL).
