# NoxFlow Feature Reality Matrix

**Audit date:** 2026-07-28
**Branch:** `inspired-rewrite`
**Commit:** `0667abd5ebe5094d461c940c6f473556767086f0`
**Shell status:** Active (PID 2285027, 217 MB RSS)
**Daemon status:** Active (PID 2190, 23 MB RSS, uptime 8h)

Each row reflects actual code inspection, runtime logs, command exits, or IPC wire
format comparison — not the claims in TASKS.md, commit messages, or plan documents.

## Status Legend

| Status | Meaning |
|--------|---------|
| **REAL** | Works in practice; tested or code-inspected to confirm correct data flow |
| **PARTIAL** | UI renders and at least one code path works, but significant gaps remain |
| **STUB** | UI shell exists but backed by placeholder, hardcoded data, or "TODO" code |
| **BROKEN** | Visible, wired, and does not work at runtime |
| **UNKNOWN** | Cannot determine without a live input (e.g. Bluetooth device pairing) |

---

## Bar

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Workspace chips show active/occupied/urgent | **REAL** | `Bar.qml:206-265` — Repeater over `workspaceEntries` with active/occupied/urgent properties from HyprlandModel |
| Workspace click switches workspace | **REAL** | `Bar.qml:248-252` — TapHandler calls `focusWorkspace()` → `runAction({ workspace_focus })`. Daemon action `WorkspaceFocus` exists and is dispatched via `hyprland::dispatch_workspace` at `main.rs:206-215` |
| Wheel scroll cycles workspace | **REAL** | `Bar.qml:253-258` — WheelHandler calls `cycleWorkspace()` |
| Weather chip shows live data | **PARTIAL** | `WeatherModel.qml:124-161` — parses wttr.in JSON correctly. But `Bar.qml:339` shows `Math.round(weatherChip._w.temperature)`. Icon at `WeatherModel.qml:134` is hardcoded `"☀️"` regardless of condition. Cache file exists at `~/.local/state/noxflow/weather.json` (24KB). |
| Media chip | **REAL** | `Bar.qml:288-317` — Shows title+artist when media model has active track |
| CPU/RAM chips | **REAL** | `SystemModel.qml:40-209` — Polls `/proc/stat`, `/proc/meminfo`, `nvidia-smi`, thermal zones every 2s |
| Network chip | **REAL** | `Bar.qml:366-378` — Shows SSID or "Offline" based on NetworkModel |
| Bluetooth chip | **REAL** | `Bar.qml:413-425` — Shows connected device name or "Bluetooth" label |
| Volume chip | **REAL** | `Bar.qml:426-438` — Shows percentage or mute icon from AudioModel |
| Battery chip | **REAL** | `Bar.qml:439-449` — Shows percentage with critical coloring |
| Notification badge | **REAL** | `Bar.qml:451-468` — Shows count via `notificationModel.notifications.length` |
| Health/degraded chip | **REAL** | `Bar.qml:470-481` — Shows warning when `providerDegraded` |
| Clock | **REAL** | `Bar.qml:486-518` — `Qt.formatTime(new Date(), "HH:mm")` with 1s timer |
| Morph chip registration | **STUB** | `Bar.qml:28-46` — `registerMorphChips()` calls `morphRegistry.registerChip()` with geometry. `MorphRegistry.qml` stores rects but nothing consumes them. |
| Tap handlers route to correct surface | **REAL** | Weather opens Dashboard, clock opens Calendar, media toggles playback, notif opens NotificationCentre |
| Multimonitor | **REAL** | `shell.qml:223-233` — `Variants { model: Quickshell.screens }` creates per-screen Bar |

## Launcher (Super+Space)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens via keybind | **REAL** | `hypr/conf/40-binds-launch.lua:8` — `noxctl launcher` → `quickshell ipc call noxctl toggleLauncher`; `shell.qml:183-209` IpcHandler routes to `toggleLauncher()` → `launcher.toggle()` |
| Escape closes it | **REAL** | `Launcher.qml:107` — `Keys.onEscapePressed: root.close()` |
| Click outside closes | **REAL** | `Launcher.qml:61` — scrim TapHandler calls `root.close()` |
| Repeated toggle safe | **REAL** | `Launcher.qml:687-689` — `toggle()` flips `launcherOpen` boolean |
| 6 modes functional | **PARTIAL** | Apps (REAL: `buildAppResults()` returns scanned + defaults), Windows (REAL: `buildWindowResults()` returns hyprland windows), Commands (REAL: hardcoded list), Calc (PARTIAL: `new Function()` eval, sanitisation is minimal), Ask AI (REAL: XHR to llama-swap), Clipboard (REAL: shows clipboard history items) |
| App scanning works | **PARTIAL** | `Launcher.qml:419-429` — Shell command `find ... -name '*.desktop'` + grep parses. Works but fragile — icon lookup is hardcoded emoji map (lines 435-451). Fails silently if `.desktop` file format deviates. |
| AI mode offline handling | **PARTIAL** | Shows "AI request failed (HTTP n)" on connection error. No retry, no fallback, no timeout display to user. |
| Calculator mode sanitisation | **FRAGILE** | `Launcher.qml:582` — `new Function("return (" + sanitized + ")")()`. Sanitisation permits spaces, `.`, `/` in `eval`-context. |
| Works when noxd disconnected | **PARTIAL** | AI, lock/suspend/reboot actions silently fail if noxd disconnected. Scrolling, desktop scan still work. |
| Loading state | **REAL** | `Launcher.qml:190-208` — Shows LoadingIndicator during AI query |
| Error state | **REAL** | `Launcher.qml:366` — "AI request failed (HTTP n)" shown |
| Has test | **NONE** | No test file found |

## Dashboard (Super+D)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens/closes | **REAL** | `Dashboard.qml:471-491` — Standard toggle with open/close animation |
| Weather display | **REAL** | `Dashboard.qml:108-196` — Shows temperature, condition, 3-day forecast grids |
| Calendar/agenda | **REAL** | `Dashboard.qml:206-292` — Mini month grid + today events from CalendarModel |
| System stats (CPU/GPU/RAM) | **REAL** | `Dashboard.qml:303-398` — Live SystemModel data, usage bars, temperatures |
| Battery | **REAL** | `Dashboard.qml:401-411` — From BatteryModel |
| Network | **REAL** | `Dashboard.qml:413-423` — From NetworkModel |
| Volume | **REAL** | `Dashboard.qml:425-435` — From AudioModel |
| Git status | **STUB** | `Dashboard.qml:29-31, 493-497` — Hardcoded `gitBranch = "main"`, `gitStatus = "clean"`. Comment: "Stub: would read from hyprland active window directory". |
| Quick actions | **PARTIAL** | Lock/suspend call noxd actions (REAL if connected). Screenshot runs `grim` directly (REAL). Refresh calls `refresh_providers` (REAL). Settings opens `gnome-control-center` (REAL). |
| Multimonitor | **REAL** | `shell.qml:126` — Singleton. `screen: Quickshell.activeScreen` — follows active screen. |
| Loading state | **PARTIAL** | Calendar sync loading shown. System stats show "--" while data loads. |
| Error state | **NONE** | No explicit error display components. |

## Overview (Super+Y)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens/closes | **REAL** | `Overview.qml:288-306` — Standard toggle |
| Escape closes | **REAL** | `Overview.qml:216` — `Keys.onEscapePressed: root.close()` |
| Scrim click closes | **REAL** | `Overview.qml:44` — TapHandler calls `root.close()` |
| Workspace list from hyprland | **REAL** | `Overview.qml:232-276` — `refreshWorkspaces()` builds from `hyprland.workspaces` with window lists |
| Click focuses workspace | **REAL** | `Overview.qml:189-193` — TapHandler calls `activateWorkspace()` → `runAction({ workspace_focus })` |
| Keyboard navigation | **REAL** | `Overview.qml:207-218` — Arrow keys, Return, Space all wired |
| Kinetic scroll | **REAL** | `Overview.qml:48-79` — Flickable + WheelHandler + smooth OutCubic animation |
| Works when noxd disconnected | **BROKEN** | `activateWorkspace()` checks `root.noxd && root.noxd.connected` — if noxd is down, workspaces can't be focused. List still renders. |
| Window previews | **PARTIAL** | Shows window titles + classes. No actual window thumbnails. |
| Multimonitor | **REAL** | `shell.qml:174` — Singleton, follows active screen |

## Capture (Super+Shift+S)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Region selection | **REAL** | `Capture.qml:92-121` — MouseArea drag with cross cursor, dimension overlay |
| Toolbar appears after select | **REAL** | `Capture.qml:119,124-154` — toolbar visible after selection confirmed |
| Copy to clipboard | **REAL** | `Capture.qml:268-271` — `grim -g REGION - | wl-copy` via sh -c |
| Save screenshot | **REAL** | `Capture.qml:273-276` — grim to `~/Pictures/Screenshots/` |
| OCR runs | **PARTIAL** | `Capture.qml:384-388` — grim → magick → tesseract pipe runs. But text shows "OCR failed. Is tesseract installed?" if tesseract isn't installed, and there's no graceful degradation. |
| TSV word overlay | **REAL** | `Capture.qml:421-487` — Second tesseract run with `tsv` output, parsed into word array, shown via WordOverlay component |
| Lens upload | **BROKEN** | `Capture.qml:278-308` — Uploads to `lens.google.com/v3/upload` via curl; opens local HTML file via `xdg-open`. The upload endpoint is unsupported and likely always returns an error page. |
| Search image | **BROKEN** | `Capture.qml:311-318` — Opens `file:///tmp/nox-capture-search.png` in browser; Google image search does not accept local file:// URLs. |
| Smart text analysis | **PARTIAL** | `Capture.qml:491-521` — regex-based classification (URL/code/dictionary/AI/search) works. But URL action opens via `xdg-open` not in-browser. AI action sends phantom `ai_query` action. |
| `forceActiveFocus` runtime error | **BROKEN** | `Capture.qml:545` — `forceActiveFocus()` called on PanelWindow which has no such method. Confirmed in journal: `ReferenceError: forceActiveFocus is not defined`. |
| Duplicate OCR pass | **INEFFICIENT** | `Capture.qml:421` — runs tesseract AGAIN for TSV output instead of requesting TSV in the first run |
| Works without noxd | **PARTIAL** | Copy, save, OCR all work without noxd. Lens/Search don't work anyway. |
| Loading state | **PARTIAL** | OCR shows "Recognizing text…" placeholder |
| Error state | **PARTIAL** | "OCR failed. Is tesseract installed?" shown |

## Control Centre (Super+Shift+B)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens/closes | **REAL** | Standard toggle via IpcHandler |
| Volume slider | **REAL** | `ControlCentre.qml:351` — `audio_set_volume` with `target: "output"`, correct daemon action |
| Brightness slider | **REAL** | `ControlCentre.qml:42` — `brightness_set` with `percentage`, correct param |
| Output mute | **REAL** | `ControlCentre.qml:238,345` — `audio_toggle_mute { target: "output" }` |
| Input mute | **REAL** | `ControlCentre.qml:379` — `audio_toggle_mute { target: "input" }` |
| Power profile | **REAL** | `ControlCentre.qml:281,316` — `power_profile_set` — daemon dispatches to power provider |
| WiFi toggle | **REAL** | `ControlCentre.qml:421` — `network_wifi_set_enabled` — daemon has handler |
| WiFi connect | **REAL** | `ControlCentre.qml:442` — `network_connect_saved` — daemon has handler |
| VPN toggle | **REAL** | `ControlCentre.qml:458` — `network_vpn_set_enabled` — daemon has handler |
| Bluetooth toggle | **REAL** | `ControlCentre.qml:484` — `bluetooth_set_powered` — daemon has handler |
| Bluetooth discover | **REAL** | `ControlCentre.qml:491` — `bluetooth_set_discovering` — daemon has handler |
| Bluetooth connect/disconnect | **REAL** | `ControlCentre.qml:519-522` — correct daemon actions |
| Audio device selector | **REAL** | `ControlCentre.qml:371,396` — `audio_set_default` with target+selector |
| NoxdClient slider coalescing | **PARTIAL** | No explicit coalescing in NoxdClient — each commitSlider call fires a new `runAction()` which is dropped if previous hasn't responded (single-request limit). |
| Debounced sliders | **PARTIAL** | `NoxIsland.qml:247-263` has sliderCommitTimer (80ms commit delay) but ControlCentre has no equivalent — rapid scrubbing via `onPositionChanged` fires `runAction` on every pixel. |

## Notification Centre (Super+N)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens/closes | **REAL** | Standard toggle via IpcHandler |
| Escape closes | **REAL** | Scrim TapHandler |
| Shows active notifications | **REAL** | Repeater over `notifModel.notifications` |
| Shows history | **REAL** | `showHistory` tab switches to `notifModel.history` |
| DND toggle | **REAL** | `notifModel.toggleDnd()` works, filters new notifications |
| Clear all | **REAL** | `notifModel.clearAll()` shifts all to history |
| Notification actions | **BROKEN** | `NotificationCentre.qml:192` — `runAction({ notification_action: { id, action } })` — **`notification_action` does not exist in the daemon Action enum.** All notification action clicks silently fail. |
| Group by app | **NONE** | Not implemented |
| Empty state | **REAL** | "No notifications" / "No history" shown |
| Loading state | **NONE** | Not applicable (model is synchronous) |
| Works without noxd | **PARTIAL** | Local model operations (add/dismiss/DND) work; notification actions don't |

## Calendar (Super+Shift+C)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens/closes | **REAL** | Standard toggle via IpcHandler |
| Month grid renders | **REAL** | `CalendarWidget.qml:97-164` — GridLayout with day cells, today highlight, event dots |
| Agenda shows events | **REAL** | `CalendarWidget.qml:167-307` — Repeater over `eventsForDay()` with expandable cards |
| Navigator buttons work | **REAL** | Prev/next month, Today button, expand toggle |
| Calendar sync runs | **REAL** | `CalendarModel.qml:151-157` — `syncGCal()` executes `python3 sync.py` process. `sync.py` at `external/waylandar-backend/sync.py` exists (10421 bytes). |
| Calendar cache loads | **REAL** | `CalendarModel.qml:48-63` — `cacheFile` FileView reads `calendar.json`. File exists: `~/.local/state/noxflow/calendar.json` (318 bytes). |
| Events render from cache | **REAL** | `calendar.json` contains valid event data ("Onam" on 2026-08-26) |
| gcalcli installed | **REAL** | `gcalcli 4.5.1` at `~/.local/bin/gcalcli` |
| OAuth secrets tracked? | **NOT VERIFIED** | `external/waylandar-backend/README.md` exists, need to check if tokens are gitignored |
| Offline behaviour | **PARTIAL** | Shows cached events when network is down. Sync timer runs every 5 min. |
| Error display | **PARTIAL** | `lastError` string set on failures but shown where? CalendarWidget doesn't display it prominently. |
| Works without noxd | **REAL** | Calendar sync and display is independent of noxd |

## NoxIsland

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Renders on screen | **REAL** | `NoxIsland.qml` — PanelWindow with `aboveWindows: true`, centered top |
| Shows startup idle state | **REAL** | `NoxIsland.qml:103-106` — `show("idle", "NoxFlow", "⊚", ...)` on startup |
| Volume slider commits to daemon | **BROKEN** | `NoxIsland.qml:255-256` — sends `volume_set` but daemon expects `audio_set_volume`. Action mismatch. |
| Brightness slider commits to daemon | **BROKEN** | `NoxIsland.qml:259-260` — sends `brightness_set` with key `value` but daemon parameter is `percentage`. | 
| Volume change from audio model shows island | **REAL** | `NoxIsland.qml:152-161` — Direct AudioModel watch shows island on volume change |
| Brightness change from model shows island | **REAL** | `NoxIsland.qml:168-178` — Direct BrightnessModel watch |
| Priority queue | **PARTIAL** | `NoxIsland.qml:37-51` — priorityMap + enqueue/dequeue exists. But `enqueueState` uses `stateQueue.concat()` + sort on every state, which is O(n log n) for what should be O(1) heap push. |
| Queue deduplication | **REAL** | `NoxIsland.qml:323-324` — Skips queuing duplicate state kinds |
| Hover expand | **REAL** | `NoxIsland.qml:57-65` — Hover expands, timeout compacts |
| Auto-hide | **REAL** | `NoxIsland.qml:191-202` — hideTimer after idle period |
| Edge gesture reveal | **REAL** | `NoxIsland.qml:111-124` — Transparent top-edge strip for auto-hide reveal |
| Media display with controls | **REAL** | `NoxIsland.qml:599-671` — Album art, title/artist, prev/play/next buttons |
| Timer | **REAL** | `NoxIsland.qml:403-409` — `startTimer(seconds)` with tick countdown |
| Recording indicator | **REAL** | `NoxIsland.qml:411-417` — `showRecording()` with 30s auto-hide |
| Notification state | **REAL** | `NoxIsland.qml:425-427` — `showNotification()` called from event handler |

## Clipboard Model

| Criterion | Status | Evidence |
|-----------|--------|----------|
| In-memory history | **REAL** | `ClipboardModel.qml:14-42` — addEntry/removeEntry/clearAll with dedup |
| Persistence (FileView JSON) | **REAL** | `ClipboardModel.qml:65-101` — storageFile reads/writes JSON via FileView. Works on first run (file doesn't exist → loads empty → creates dir for writes). |
| Auto-capture | **STUB** | `ClipboardModel.qml:3` — Comment: "Future: use wl-paste watch or noxd clipboard provider for auto-capture." No auto-capture implementation. |
| Launcher integration | **REAL** | `ClipboardModel.qml:125-140` — `asLauncherItems()` formats entries for launcher display |
| Corruption handling | **REAL** | `ClipboardModel.qml:89-91` — Catches JSON parse errors silently |

## Theme Profiles

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Profile switching works in-memory | **REAL** | `SettingsPanel.qml:200-207` — `Tokens.applyProfile()` changes tokens at runtime |
| 5 profiles exist | **REAL** | Settings panel lists: expressive, focus, ambient, performance, oled |
| Persistence | **NOT WIRED** | Setting calls `noxd.setSetting("appearance.profile", ...)` but daemon's `SetSetting` handler returns `SettingUpdated` without persisting anything (`main.rs:187-189`: just echoes back). |
| Density/radius/motion controls | **REAL** | Controls exist and modify Tokens reactively |
| Reduced motion honored | **REAL** | `Tokens.reducedMotion` checked in NoxIsland `deactivate()` and animation behaviors |

## Morphing System

| Criterion | Status | Evidence |
|-----------|--------|----------|
| MorphRegistry stores chip rects | **REAL** | `MorphRegistry.qml:12-14` — `registerChip(id, rect)` stores in `chips` map |
| Bar registers 4 chips | **REAL** | `Bar.qml:39-46` — clock, media, notification, status registered |
| Any surface reads source geometry | **NONE** | No surface reads `morphRegistry.chipRect()` anywhere |
| MorphingSurface animation engine | **NONE** | `MorphingSurface.qml` does not exist |
| Actual geometric morph | **NONE** | All surface transitions are scale+opacity fades. No geometry interpolation. |
| Reality | **STUB** | Registry scaffold exists, nothing consumes it |

## Weather Model

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Fetches wttr.in | **REAL** | `WeatherModel.qml:51-54` — curl to wttr.in with format=j1 |
| Parses JSON | **REAL** | `WeatherModel.qml:124-162` — Full parse of current_condition + 3-day forecast |
| Caches to FileView | **REAL** | `WeatherModel.qml:77-81,89-103` — Cache read/write via FileView |
| Timer refetches | **REAL** | `WeatherModel.qml:114-121` — 10-minute fetchTimer |
| Icon mapping | **BROKEN** | `WeatherModel.qml:134,151` — Icon hardcoded to `"☀️"` always. No wttr.in weather code → emoji mapping. |
| Error handling | **PARTIAL** | Sets `lastError` + console.warn on fetch/parse failure |
| Works offline | **PARTIAL** | Shows cached data if available. If no cache, shows empty. |

## System Model

| Criterion | Status | Evidence |
|-----------|--------|----------|
| CPU usage | **REAL** | `SystemModel.qml:48-101` — `/proc/stat` deltas every 2s |
| Memory | **REAL** | `SystemModel.qml:103-131` — `/proc/meminfo` parsed |
| GPU (NVIDIA) | **REAL** | `SystemModel.qml:132-182` — `nvidia-smi` query with fallback to AMD |
| Temperature | **REAL** | `SystemModel.qml:184-209` — thermal zones + sensors fallback |
| Polling timer | **REAL** | `SystemModel.qml:25-30` — 2000ms interval |

## NoxdClient

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Unix socket connect | **REAL** | `NoxdClient.qml:40-48` — Socket to `$XDG_RUNTIME_DIR/noxflow/noxd.sock` |
| Protocol negotiation | **REAL** | `NoxdClient.qml:119-128` — Version check with protocol v1 |
| State subscription | **REAL** | `NoxdClient.qml:130-153` — get_state → subscribe with snapshot dispatch |
| Event stream | **REAL** | `NoxdClient.qml:175-190` — Incoming events dispatched via `eventReceived` signal + snapshot updates |
| Reconnection with backoff | **REAL** | `NoxdClient.qml:96-99` — Exponential backoff 250ms→8s |
| Single in-flight request | **BROKEN** | `NoxdClient.qml:108` — `if (pending !== null) return false`. Any second action is silently dropped while first is in flight. For a daemon that responds synchronously this shouldn't happen, but rapid invocations will lose actions. |
| Response timeout | **NONE** | No timeout on pending requests — if daemon never responds, `pending` stays `null` forever, blocking all subsequest requests. |
| Malformed event handling | **REAL** | `NoxdClient.qml:176` — checks `Protocol.providers.indexOf(event.provider)`, drops events from unknown providers |
| Stream ID change detection | **REAL** | `NoxdClient.qml:177-179` — Disconnects if stream_id changes |
| Health tracking | **REAL** | `NoxdClient.qml:199-203` — Provider health map updated per event |
| Failure visibility to UI | **PARTIAL** | `lastError` exposed but not prominently displayed in UI |

## QuickSnipSettings (capture config)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Exists as QML object | **REAL** | `shell.qml:33` — `CaptureSurface.QuickSnipSettings { id: quickSnipSettings; Component.onCompleted: load() }` |
| Settings persisted | **UNKNOWN** | `QuickSnipSettings.qml` at `surfaces/capture/QuickSnipSettings.qml`? Need to verify. |

## Radial Wheel

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Opens via IPC | **REAL** | `shell.qml:111-123` — Per-screen Variants with IpcHandler |
| Canvas rendered | **REAL** | RadialWheel.qml exists at `surfaces/radialmenu/RadiualWheel.qml` (note path has hyphen — `radiual-menu` in filesystem?) |
| Editable slots | **STUB** | No `loadConfig()` observable in code — listed as deferred in PLAN.md |

## Additional Runtime Observations

- **Shell memory:** 217 MB RSS (peak 370 MB) — high for a QML shell displaying bars and simple surfaces
- **Daemon CPU:** 5h22m CPU over 8h uptime — noise-like polling or busy-wait in some provider
- **Daemon errors:** Repeated `"Resource temporarily unavailable (os error 11)"` — suggests race between client connect/disconnect and socket accept loop
- **Clipboard first-run warning:** `FileView: file does not exist` for clipboard.json — benign but noted
