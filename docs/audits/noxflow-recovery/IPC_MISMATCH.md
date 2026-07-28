# NoxFlow IPC Protocol Mismatch Audit

**Source of truth:** `core/noxflow-ipc/src/lib.rs` — `Action` enum (lines 52-142)

Each QML `runAction()` call was compared against the Rust enum variants. Every
entry below cites exact file, line, and the daemon's actual expected shape.

## Canonical Action Enum (daemon side)

Defined at `core/noxflow-ipc/src/lib.rs:52-142`:

| Variant | Fields | Type |
|---------|--------|------|
| `WorkspaceFocus` | `workspace: String` | Action |
| `WorkspaceCycle` | `delta: i16` | Action |
| `Lock` | *(none)* | Action |
| `Suspend` | *(none)* | Action |
| `Reboot` | *(none)* | Action |
| `PowerOff` | *(none)* | Action |
| `RefreshProviders` | *(none)* | Action |
| `SetProfile` | `profile: String` | Action |
| `AudioSetVolume` | `target: AudioTarget, volume: u8` | Action |
| `AudioAdjustVolume` | `target: AudioTarget, delta: i16` | Action |
| `AudioToggleMute` | `target: AudioTarget` | Action |
| `AudioSetDefault` | `target: AudioTarget, selector: String` | Action |
| `BrightnessSet` | `percentage: u8` | Action |
| `BrightnessAdjust` | `delta: i16` | Action |
| `PowerProfileSet` | `profile: String` | Action |
| `NetworkWifiSetEnabled` | `enabled: bool` | Action |
| `NetworkConnectSaved` | `uuid: String` | Action |
| `NetworkDisconnectWifi` | *(none)* | Action |
| `NetworkRefresh` | *(none)* | Action |
| `NetworkVpnSetEnabled` | `uuid: String, enabled: bool` | Action |
| `BluetoothSetPowered` | `powered: bool` | Action |
| `BluetoothSetDiscovering` | `discovering: bool` | Action |
| `BluetoothConnect` | `device_id: String` | Action |
| `BluetoothDisconnect` | `device_id: String` | Action |
| `BluetoothSetTrusted` | `device_id: String, trusted: bool` | Action |
| `MediaPlay` | *(none)* | Action |
| `MediaPause` | *(none)* | Action |
| `MediaPlayPause` | *(none)* | Action |
| `MediaPrevious` | *(none)* | Action |
| `MediaNext` | *(none)* | Action |
| `MediaSeek` | `offset_us: i64` | Action |
| `MediaSelectPlayer` | `player: String` | Action |
| `IslandTestVolume` | `volume: u8` | Action |
| `IslandTestOutputMute` | `muted: bool` | Action |
| `IslandTestInputMute` | `muted: bool` | Action |
| `IslandTestBrightness` | `percentage: u8` | Action |

## QML send-side summary

Every `runAction()` call in `shell/noxflow/` was extracted.

### Category 1: CORRECT — Wire format matches daemon

These QML calls produce JSON that the daemon serde deserializer accepts:

| QML call | File:Line | Daemon variant | Notes |
|----------|-----------|----------------|-------|
| `workspace_focus: { workspace: name }` | `Bar.qml:137` | `WorkspaceFocus` | Correct |
| `workspace_focus: { workspace: ws.name }` | `Overview.qml:282` | `WorkspaceFocus` | Correct |
| `workspace_cycle: { delta: delta }` | `Bar.qml:141` | `WorkspaceCycle` | Correct |
| `audio_toggle_mute: { target: "output" }` | `Bar.qml:145`, `ControlCentre.qml:238,345` | `AudioToggleMute` | Correct |
| `audio_set_volume: { target: "output", volume: … }` | `ControlCentre.qml:46,351` | `AudioSetVolume` | Correct |
| `audio_set_default: { target: "output", selector: … }` | `ControlCentre.qml:371` | `AudioSetDefault` | Correct |
| `audio_set_default: { target: "input", selector: … }` | `ControlCentre.qml:396` | `AudioSetDefault` | Correct |
| `audio_toggle_mute: { target: "input" }` | `ControlCentre.qml:379` | `AudioToggleMute` | Correct |
| `brightness_set: { percentage: … }` | `ControlCentre.qml:42` | `BrightnessSet` | Correct |
| `power_profile_set: { profile: … }` | `ControlCentre.qml:281,316` | `PowerProfileSet` | Correct |
| `network_wifi_set_enabled: { enabled: … }` | `ControlCentre.qml:421` | `NetworkWifiSetEnabled` | Correct |
| `network_connect_saved: { uuid: … }` | `ControlCentre.qml:442` | `NetworkConnectSaved` | Correct |
| `network_vpn_set_enabled: { uuid, enabled }` | `ControlCentre.qml:458` | `NetworkVpnSetEnabled` | Correct |
| `network_refresh: {}` | `Bar.qml:149` | `NetworkRefresh` | Correct |
| `bluetooth_set_powered: { powered: … }` | `Bar.qml:153`, `ControlCentre.qml:484` | `BluetoothSetPowered` | Correct |
| `bluetooth_set_discovering: { discovering }` | `ControlCentre.qml:491` | `BluetoothSetDiscovering` | Correct |
| `bluetooth_connect: { device_id: … }` | `ControlCentre.qml:522` | `BluetoothConnect` | Correct |
| `bluetooth_disconnect: { device_id: … }` | `ControlCentre.qml:519` | `BluetoothDisconnect` | Correct |
| `media_play_pause: {}` | `Bar.qml:157`, `NoxIsland.qml:663` | `MediaPlayPause` | Correct |
| `media_previous: {}` | `NoxIsland.qml:658` | `MediaPrevious` | Correct |
| `media_next: {}` | `NoxIsland.qml:668` | `MediaNext` | Correct |
| `lock: {}` | `Dashboard.qml:458`, `Launcher.qml:618` | `Lock` | Correct |
| `suspend: {}` | `Dashboard.qml:459`, `Launcher.qml:622` | `Suspend` | Correct |
| `reboot: {}` | `Launcher.qml:626` | `Reboot` | Correct |
| `power_off: {}` | `Launcher.qml:630` | `PowerOff` | Correct |
| `refresh_providers: {}` | `Dashboard.qml:462` | `RefreshProviders` | Correct |

### Category 2: BROKEN — Key mismatch (wrong action name or parameter key)

#### 2a. `NoxIsland.qml:256` — volume_set (wrong action name)

```qml
// File: shell/noxflow/NoxIsland.qml:255-256
root.noxd.runAction({ volume_set: { value: clamped * root.activityMaximum } });
```

**Wire JSON (sent):**
```json
{"version":1,"id":"shell-3","method":"run_action","params":{"action":{"volume_set":{"value":42.0}}}}
```

**Daemon expects:**
```json
{"action":{"audio_set_volume":{"target":"output","volume":42}}}
```

**Root cause:** `volume_set` is not a variant of `enum Action`. The correct action
name is `audio_set_volume` with fields `target` (AudioTarget) and `volume` (u8).

**Impact:** Volume slider in NoxIsland never reaches daemon. All volume changes
through the island slider are silently dropped — `runAction()` returns `false`
(because NoxdClient checks `connected` which is true, but the daemon returns
`UnknownAction` error, and the error is logged but not visible to the user).

---

#### 2b. `NoxIsland.qml:260` — brightness_set with wrong parameter key

```qml
// File: shell/noxflow/NoxIsland.qml:259-260
root.noxd.runAction({ brightness_set: { value: clamped * root.activityMaximum } });
```

**Wire JSON (sent):**
```json
{"version":1,"id":"shell-4","method":"run_action","params":{"action":{"brightness_set":{"value":73.0}}}}
```

**Daemon expects:**
```json
{"action":{"brightness_set":{"percentage":73}}}
```

**Root cause:** `BrightnessSet` field is `percentage: u8`, not `value: f64`.
The `value` key does not match. Serde deserialization likely returns
`InvalidParams` or the default value for missing field (0).

**Impact:** NoxIsland brightness slider doesn't work. User drags the island
slider, value is shown in the UI, but the daemon ignores it.

---

### Category 3: PHANTOM — Action name not in daemon enum at all

These actions are sent by QML but **do not exist** in the `Action` enum at
`core/noxflow-ipc/src/lib.rs:52-142`. The daemon routes unmatched actions to
a `_ => {}` catch-all at `main.rs:335` which silently accepts them (returns
`ActionAccepted` anyway due to `main.rs:337`) but performs no work.

| Action name | QML source | File:Line | Used for |
|-------------|-----------|-----------|----------|
| `window_focus` | `Launcher.qml:613` | `Launcher.qml:613` | Focus window by address |
| `ai_query` | `Capture.qml:531` | `Capture.qml:531` | Send OCR text to AI |
| `notification_action` | `NotificationCentre.qml:192` | `NotificationCentre.qml:192` | Notification action invocation |
| `toggle_launcher` | `RadialWheel.qml:246` | `RadialWheel.qml:246` | Toggle launcher from radial wheel |

**Daemon behaviour for all four:** `handle_request()` at line 245 does
`action.clone()`, matches none of the specific branches, hits `_ => {}` at
line 335, then returns `Response::ActionAccepted(ActionAccepted { action })`.
The daemon says "OK, accepted" but does **nothing**.

---

### Category 4: NoxdClient request pipeline defects

`NoxdClient.qml` (`shell/noxflow/NoxdClient.qml`):

| Issue | Location | Detail |
|-------|----------|--------|
| Single in-flight limit | `NoxdClient.qml:108` | `if (pending !== null) return false` — second concurrent action silently dropped |
| No response timeout | `NoxdClient.qml:108-117` | If daemon never responds, `pending` stays non-null forever; all future actions blocked |
| No request queue | Throughout | No FIFO or priority queue for actions |
| Slider-event coalescing absent | None | Rapid slider drags fire `runAction` on every pixel. NoxIsland has 80ms debounce (`sliderCommitTimer`) but `ControlCentre.qml` does not. |
| Error visibility to UI | `NoxdClient.qml:206-210` | `failProtocol()` sets `errorText` and disconnects; no UI component reads this prominently |

---

## Summary Table

| Category | Count | Impact |
|----------|-------|--------|
| Correct (works) | ~25 actions | Real |
| Key mismatch (broken) | 2 actions | NoxIsland sliders don't work |
| Phantom (silent no-op) | 4 actions | Window focus, AI query, notification action, toggle launcher do nothing when noxd is connected |
| Request pipeline (all modes) | 1 structural | All actions dropped when another action is in flight; no timeout recovery |
