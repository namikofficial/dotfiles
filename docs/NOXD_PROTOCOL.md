# NoxD IPC Protocol v1

> The wire contract shared by `noxd` (daemon), `noxctl` (CLI), and the
> Quickshell-based NoxFlow shell. All three sides are maintained in-tree.

---

## 1. Transport

- **Type**: Unix domain socket (`AF_UNIX`, `SOCK_STREAM`).
- **Path**: `$XDG_RUNTIME_DIR/noxflow/noxd.sock`
  - Fallback: `/tmp/noxflow/noxd.sock` when `$XDG_RUNTIME_DIR` is unset.
- **Permissions**: Socket directory `mode 0700`, socket file `mode 0600`.
- **Directory ownership**: Stale socket cleanup validates device + inode identity.

---

## 2. Framing

Messages are **newline-delimited JSON (NDJSON)**.

- Every request, response, and event is a single compact JSON object,
  serialised without unnecessary whitespace, terminated by `\n`.
- **Maximum frame size**: 64 KiB (`MAX_FRAME_BYTES = 65536`).
  - Larger frames cause an immediate disconnect without a response.
- **Encoding**: UTF-8.

---

## 3. Protocol Version Negotiation

- Current protocol version: **`1`**.
- Each **request** carries a `version` field in its envelope.
- The daemon validates the version on every request.
- Unsupported versions are rejected with error code
  `unsupported_protocol_version`, including the requested version and
  the list of supported versions.
- The client should obtain the daemon version via `get_version` after
  connecting to confirm compatibility before subscribing.

---

## 4. Request Shape

```json
{
  "version": 1,
  "id": "unique-request-id",
  "method": "method_name",
  "params": { ... }
}
```

| Field    | Type   | Required | Description |
|----------|--------|----------|-------------|
| `version` | u32   | yes      | Protocol version number (`1`). |
| `id`     | string | yes      | Opaque request identifier echoed in the response. |
| `method` | string | yes      | Method name (see §4.1). |
| `params` | object | per-method | Payload specific to the method. |

`id` must be unique per-connection. A response may arrive out of order
only if the client has multiple requests in flight — the `id` field
disambiguates. The daemon processes requests serially per connection so
responses arrive in order for a single-client, single-pending design, but
the protocol supports multiplexing.

### 4.1 Method Registry

| Method              | Params | Description |
|---------------------|--------|-------------|
| `ping`              | —      | Connectivity check. Returns `pong`. |
| `get_version`       | —      | Returns daemon and protocol version info. |
| `get_state`         | —      | Full snapshot of all providers + settings. |
| `get_provider_state`| `{ provider }` | Snapshot of a single provider. |
| `get_setting`       | `{ key }` | Read a single persisted setting. |
| `get_settings`      | —      | Read all persisted settings. |
| `set_setting`       | `{ key, value }` | Write a setting (validated). |
| `subscribe`         | `{ providers, event_types? }` | Start receiving events. |
| `unsubscribe`       | `{ subscription_id }` | Stop receiving events. |
| `run_action`        | `{ action }` | Execute a mutating action (see §4.2). |

#### 4.1.1 `get_setting`

```
{ "key": "appearance.profile" }
```

Returns `setting` result with the current value, or error
`unknown_setting` if the key has not been set.

#### 4.1.2 `get_settings`

No params. Returns `settings` result with a flat map of all persisted
settings.

#### 4.1.3 `set_setting`

```
{ "key": "appearance.profile", "value": "material-oled" }
```

The daemon validates the value (type, range, allowed values). If valid,
the value is persisted and broadcast via a `setting_changed` event.
Returns `setting_updated` on success or `invalid_params` on validation
failure.

---

### 4.2 Action Registry (Canonical)

Every action is sent as `{ "action": { "action_name": { params } } }`
inside a `run_action` request.

#### 4.2.1 Workspace

| Action name | Params | Description | Fallback |
|-------------|--------|-------------|----------|
| `workspace_focus` | `{ workspace: string }` | Switch to workspace by name/id | `hyprctl dispatch workspace <id>` |
| `workspace_cycle` | `{ delta: integer }` | Cycle workspaces (±1) | `hyprctl dispatch workspace ±1` |

#### 4.2.2 System / Power

| Action name | Params | Retry policy | Fallback |
|-------------|--------|-------------|----------|
| `lock` | — | never retry | `loginctl lock-session` |
| `suspend` | — | never retry | `systemctl suspend` |
| `reboot` | — | never retry, confirmation required | none |
| `power_off` | — | never retry, confirmation required | none |
| `set_profile` | `{ profile: string }` | retry once | none |

#### 4.2.3 Audio

| Action name | Params | Coalesce |
|-------------|--------|----------|
| `audio_set_volume` | `{ target: "output"\|"input", volume: 0-255 }` | yes (by target) |
| `audio_adjust_volume` | `{ target: "output"\|"input", delta: integer }` | yes (by target) |
| `audio_toggle_mute` | `{ target: "output"\|"input" }` | no |
| `audio_set_default` | `{ target: "output"\|"input", selector: string }` | no |

#### 4.2.4 Brightness

| Action name | Params | Coalesce |
|-------------|--------|----------|
| `brightness_set` | `{ percentage: 0-100 }` | yes |
| `brightness_adjust` | `{ delta: integer }` | yes |

#### 4.2.5 Power Profile

| Action name | Params |
|-------------|--------|
| `power_profile_set` | `{ profile: string }` |

#### 4.2.6 Network

| Action name | Params |
|-------------|--------|
| `network_wifi_set_enabled` | `{ enabled: bool }` |
| `network_connect_saved` | `{ uuid: string }` |
| `network_disconnect_wifi` | — |
| `network_refresh` | — |
| `network_vpn_set_enabled` | `{ uuid: string, enabled: bool }` |

#### 4.2.7 Bluetooth

| Action name | Params |
|-------------|--------|
| `bluetooth_set_powered` | `{ powered: bool }` |
| `bluetooth_set_discovering` | `{ discovering: bool }` |
| `bluetooth_connect` | `{ device_id: string }` |
| `bluetooth_disconnect` | `{ device_id: string }` |
| `bluetooth_set_trusted` | `{ device_id: string, trusted: bool }` |

#### 4.2.8 Media

| Action name | Params |
|-------------|--------|
| `media_play` | — |
| `media_pause` | — |
| `media_play_pause` | — |
| `media_previous` | — |
| `media_next` | — |
| `media_seek` | `{ offset_us: i64 }` |
| `media_select_player` | `{ player: string }` |

#### 4.2.9 Island Test (Synthetic)

> Used by the Nox Island for UI previews. These publish test events
> without interacting with real hardware.

| Action name | Params |
|-------------|--------|
| `island_test_volume` | `{ volume: 0-255 }` |
| `island_test_output_mute` | `{ muted: bool }` |
| `island_test_input_mute` | `{ muted: bool }` |
| `island_test_brightness` | `{ percentage: 0-100 }` |

---

## 5. Response Shape

```json
{
  "version": 1,
  "id": "echoed-request-id",
  "result": { "type": "...", "data": { ... } },
  "error": null
}
```

Every response has exactly one of `result` or `error` (never both, never
neither).

### 5.1 Result Types

| Type | Data | Triggered by |
|------|------|-------------|
| `pong` | — | `ping` |
| `version` | `{ daemon_version, protocol_version, supported_protocol_versions }` | `get_version` |
| `state` | `{ timestamp, providers, settings }` | `get_state` |
| `provider_state` | `{ provider, status, data }` | `get_provider_state` |
| `subscription` | `{ subscription_id, stream_id, sequence, snapshots }` | `subscribe` |
| `setting_updated` | `{ key, value }` | `set_setting` |
| `setting` | `{ key, value }` | `get_setting` |
| `settings` | `{ settings: { key: value, ... } }` | `get_settings` |
| `action_accepted` | `{ action }` | `run_action` |

### 5.2 Error Shape

```json
{
  "version": 1,
  "id": "echoed-request-id",
  "result": null,
  "error": {
    "code": "error_code",
    "message": "Human-readable description",
    "details": {}
  }
}
```

### 5.3 Error Codes

| Code | Meaning |
|------|---------|
| `invalid_request` | JSON parse error, missing `id`, invalid UTF-8 |
| `unsupported_protocol_version` | Client requested an unsupported version |
| `unknown_method` | Method string does not match any variant |
| `invalid_params` | Params are the wrong type, missing fields, or fail validation |
| `unknown_provider` | Provider name not registered on the event bus |
| `unknown_setting` | Setting key does not exist |
| `unknown_action` | Action name does not match any variant |
| `unsupported` | Generic provider-level action failure |
| `not_subscribed` | Subscription ID does not exist |
| `internal` | Bus closed, already registered, or poisoned mutex |

---

## 6. Subscription / Events

### 6.1 Subscribe Flow

1. Client sends `subscribe { providers: ["audio", "brightness", ...] }`.
2. Daemon allocates a `subscription_id`, captures snapshots of matching
   providers, creates a bounded event channel (capacity 256).
3. Daemon returns `subscription` ACK with `snapshots` map.
4. Daemon pushes events asynchronously over the same connection.

### 6.2 Event Envelope

```json
{
  "version": 1,
  "timestamp": 1700000000,
  "stream_id": "pid-1234567890-1",
  "sequence": 42,
  "provider": "audio",
  "event_type": "state_changed",
  "schema_version": 1,
  "data": { ... provider-specific state ... }
}
```

| Field | Description |
|-------|-------------|
| `stream_id` | Stable per-connection identifier for this session. Clients should validate `stream_id` matches the subscription ACK. A mismatch indicates stale state. |
| `sequence` | Monotonically increasing event counter. Gaps indicate dropped events (slow subscriber). |
| `provider` | Provider name (e.g. `"audio"`, `"brightness"`, etc.). |
| `event_type` | `"state_changed"` for all current providers. Future: `"backend_unavailable"`, `"backend_recovered"`. |
| `data` | Complete provider state snapshot (same shape as `provider_state` data). |

### 6.3 Event Providers

| Provider name | Emitted by | Data shape |
|---------------|-----------|------------|
| `settings` | Settings manager | `{ key, value }` — a setting was changed |
| `hyprland` | Hyprland provider | `{ active_workspace, workspaces, active_window, monitors, ... }` |
| `audio` | Audio provider | `{ output_volume, input_volume, output_muted, input_muted, outputs, inputs, ... }` |
| `brightness` | Brightness provider | `{ percentage, minimum, step, backend_available, ... }` |
| `power` | Power provider | `{ battery_present, percentage, charging_state, active_profile, ... }` |
| `network` | Network provider | `{ connectivity, connected_ssid, signal_strength, wifi_enabled, ... }` |
| `bluetooth` | Bluetooth provider | `{ adapter_present, powered, discovering, devices, ... }` |
| `media` | Media provider | `{ players, active, ... }` |

### 6.4 Event Ordering

- Events within a single provider are ordered by `sequence`.
- Events across different providers have no guaranteed ordering.
- The first event(s) after a subscription ACK reflect state changes
  that occurred after the snapshot was captured.
- A slow subscriber (bounded channel full) is silently dropped:
  - The subscriber channel has capacity 256.
  - If `try_send` fails, the subscriber is unregistered and counted
    as `dropped_subscribers`.
  - The client should detect the lack of events and resubscribe.

### 6.5 Provider Snapshots

Every event `data` field contains a complete snapshot of the provider's
current state. Clients should replace their entire cached state for
that provider, not merge incrementally.

---

## 7. Settings Persistence

### 7.1 Read Flow

```
client → get_setting { key: "appearance.profile" }
        → get_settings  (all settings)
daemon → setting { key, value }
        → settings { settings: { ... } }
```

### 7.2 Write Flow

```
client → set_setting { key: "appearance.profile", value: "material-oled" }
daemon → setting_updated { key, value }
        → event { provider: "settings", event_type: "changed", data: { key, value } }
```

### 7.3 Canonical Settings

| Key | Type | Default | Validation |
|-----|------|---------|------------|
| `appearance.profile` | string | `"material-expressive"` | Must match a known profile name |
| `appearance.density` | string | `"comfortable"` | `compact`, `comfortable`, `spacious` |
| `appearance.radius` | u32 | `14` | 0–36 |
| `shell.reduced_motion` | bool | `false` | boolean |
| `bar.mode` | string | `"normal"` | `normal`, `compact`, `auto-hide` |
| `ai.provider` | string | `"local"` | non-empty |
| `ai.endpoint` | string | `"http://127.0.0.1:8080/v1"` | valid URL |
| `ai.model` | string | `"qwen3-4b-local"` | non-empty |
| `calendar.sync_enabled` | bool | `false` | boolean |
| `island.enabled` | bool | `true` | boolean |
| `animation.speed` | f64 | `1.0` | 0.0–2.0 |

### 7.4 Secrets

API keys (`ai.api_key`) are stored **separately** in
`$XDG_STATE_HOME/noxflow/secrets.json` with `0600` permissions.

- They are **never returned** by `get_setting` or `get_settings`.
- They are **redacted** in all logs by `sanitize()`.
- They can only be **set**, never read back.
- Validate on write (non-empty string).

### 7.5 Storage

- **Settings**: `$XDG_STATE_HOME/noxflow/settings.json`
- **Secrets**: `$XDG_STATE_HOME/noxflow/secrets.json`
- Storage uses atomic writes (write to `.tmp`, `fsync`, rename).

---

## 8. Connection Lifecycle

### 8.1 Handshake

```
client connect
  → server accepts, spawns client thread
client → get_version
server → version { daemon_version, protocol_version, supported_versions }
client (validates version compatibility)
client → get_state
server → state { providers, settings }
client → subscribe { providers: [...] }
server → subscription { subscription_id, stream_id, sequence, snapshots }
client → [operational]
```

### 8.2 Reconnection

1. Client detects socket disconnect (read error / write error / EOF).
2. Client clears all pending requests (calls each error callback).
3. Client clears subscription state.
4. Client waits (exponential backoff: 250ms → 500ms → ... → 8s max).
5. Client retries connect.
6. On success: repeat handshake from `get_version` onward.
7. Client re-settings any stored settings that were not yet confirmed.

### 8.3 Disconnect

- Server detects client disconnect when `read_frame()` returns EOF.
- All of the client's subscriptions are cleaned up.
- If a frame exceeds 64 KiB, the client is disconnected immediately
  without a response.

---

## 9. Timeouts

| Timeout | Value | Action |
|---------|-------|--------|
| Client read (daemon side) | 1 s | Thread exits on timeout |
| Client write (daemon side) | 1 s | Thread exits on timeout |
| Request timeout (client side) | 2 s (default) | Error callback, clear request slot |
| Connection timeout (CLI) | 2 s (configurable via `--timeout-ms`) | `CliError::Timeout` |
| Accept poll interval | 50 ms | Sleep between accept attempts |

---

## 10. Backward Compatibility

- The `version` field on every request allows future protocol changes.
- `SUPPORTED_PROTOCOL_VERSIONS` is returned in the `version` response.
- New fields in responses and events MUST be additive (clients ignore
  unknown fields — serde `#[serde(deny_unknown_fields)]` is NOT used).
- Deprecated actions are kept for at least one minor version with a
  log warning before removal.
- Settings keys are additive — removing a key is a major version change.

---

## 11. Offline / Fallback Policy

When noxd is unreachable, certain essential actions have safe direct
fallbacks using system commands. Fallback use is always logged.

| Action | Fallback | Condition |
|--------|----------|-----------|
| `workspace_focus` | `hyprctl dispatch workspace <id>` | `$HYPRLAND_INSTANCE_SIGNATURE` set |
| `workspace_cycle` | `hyprctl dispatch workspace ±1` | `$HYPRLAND_INSTANCE_SIGNATURE` set |
| `lock` | `loginctl lock-session` | Always |
| `suspend` | `systemctl suspend` | Always |
| `screenshot` | `grimblast copy` or `grim` | Always |

Actions NOT listed here (audio, brightness, network, bluetooth, media,
power profile) require the daemon and will report an error when it is
unreachable.

Destructive actions (`reboot`, `power_off`) are NEVER retried or
executed as fallback when the daemon is unreachable.

---

## 12. Implementation Notes

### 12.1 Coalescing (Client-Side)

Rapid continuous actions should be coalesced to avoid flooding:

| Action group | Coalesce key | Behavior |
|-------------|-------------|----------|
| `brightness_set` / `brightness_adjust` | `"brightness"` | Keep latest unsent value |
| `audio_set_volume` / `audio_adjust_volume` | `"volume::output"` or `"volume::input"` | Keep latest unsent value |
| `workspace_focus` | `"workspace::<id>"` | Only coalesce same workspace ID |
| `network_refresh` | `"refresh"` | Coalesce with 500ms debounce |
| Everything else | — | No coalescing |

### 12.2 Retry Policy

| Action category | Retry? |
|----------------|--------|
| Read-only (`ping`, `get_version`, `get_state`, `get_provider_state`, `get_setting`, `get_settings`) | Once on timeout |
| Read-only subscriptions (`subscribe`, `unsubscribe`) | Once on timeout |
| Idempotent writes (`set_setting`, `brightness_set`, `audio_set_volume`, etc.) | Once on timeout |
| Destructive (`reboot`, `power_off`, `suspend`) | Never |

### 12.3 Request IDs

Request IDs SHOULD be monotonically increasing per connection. Format:
`<prefix>-<counter>` (e.g. `shell-1`, `shell-2`, `ctl-1`, `ctl-2`).

---

## 13. Changelog

| Version | Changes |
|---------|---------|
| 1 (initial) | All methods above, 34 actions, 7 providers, subscription/event stream, settings get/set with persistence |
