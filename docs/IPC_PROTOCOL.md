# NoxFlow IPC protocol

This document defines protocol version `1` between `noxd`, `noxctl`, and
Quickshell. Transport is newline-independent JSON over the Unix domain socket:

```text
$XDG_RUNTIME_DIR/noxflow/noxd.sock
```

If `XDG_RUNTIME_DIR` is unset, the current implementation falls back to
`/tmp/noxflow/noxd.sock`.

## Envelopes

Every request has a client-generated string `id` and a numeric `version`.
Responses echo the request `id`. A response contains exactly one of `result`
or `error`.

```json
{"version":1,"id":"req-1","method":"ping"}
```

```json
{"version":1,"id":"req-1","result":{"type":"pong"}}
```

Events are unsolicited messages. They always include the protocol version,
Unix timestamp in seconds, provider name, event type, and optional data:

```json
{"version":1,"timestamp":1710000000,"provider":"audio","event_type":"volume_changed","data":{"volume":42}}
```

Unknown JSON fields must be ignored by clients. Clients should likewise ignore
unknown result types, event types, and provider data introduced in compatible
versions.

## Requests

Supported methods and parameters are:

| Method | Parameters |
| --- | --- |
| `ping` | none |
| `get_version` | none |
| `get_state` | none |
| `get_provider_state` | `provider` |
| `subscribe` | `providers`, `event_types` |
| `unsubscribe` | `subscription_id` |
| `set_setting` | `key`, JSON `value` |
| `run_action` | typed `action` object |

Examples:

```json
{"version":1,"id":"req-2","method":"get_version"}
{"version":1,"id":"req-3","method":"get_provider_state","params":{"provider":"audio"}}
{"version":1,"id":"req-4","method":"subscribe","params":{"providers":["audio"],"event_types":["volume_changed"]}}
{"version":1,"id":"req-5","method":"set_setting","params":{"key":"profile","value":"focus"}}
{"version":1,"id":"req-6","method":"run_action","params":{"action":{"set_profile":{"profile":"focus"}}}}
```

`run_action` is intentionally an enum of named actions: `lock`, `suspend`,
`reboot`, `power_off`, `refresh_providers`, and `set_profile`. There is no IPC
operation for executing a shell command or passing an executable and its
arguments.

## Responses and errors

`get_version` returns the daemon version, active protocol version, and the list
of supported protocol versions. For an unsupported version, the daemon returns
a response such as:

```json
{"version":1,"id":"req-7","error":{"code":"unsupported_protocol_version","message":"unsupported protocol version","details":{"requested_version":"2","supported_versions":"[1]"}}}
```

Error codes are `invalid_request`, `unsupported_protocol_version`,
`unknown_method`, `invalid_params`, `unknown_provider`, `unknown_setting`,
`unknown_action`, `not_subscribed`, and `internal`. Error objects are stable
and structured; `details` may gain fields over time.

## Rust types

The canonical Serde definitions live in
[`core/noxflow-ipc/src/lib.rs`](../core/noxflow-ipc/src/lib.rs). Both Rust
clients use this crate; Quickshell can consume the JSON representation without
linking to Rust.
