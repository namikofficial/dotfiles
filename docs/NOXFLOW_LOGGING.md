# NoxFlow diagnostics and logs

`noxd` writes one structured JSON record per diagnostic event to stderr. The
user systemd service sends stderr to the journal, where the records can be
inspected without creating application log files.

Records contain a timestamp, level, event, component, and process ID. Request
IDs and provider names are included only when relevant. Diagnostic messages
are bounded and sensitive-looking values, credentials, tokens, and clipboard
contents are never emitted.

Levels are `trace`, `debug`, `info`, `warn`, and `error`. Startup, readiness,
shutdown, malformed input, provider failures, and panic events have explicit
event names. Repeated failures for one provider emit immediately once, then
are suppressed for 30 seconds; the next emitted failure reports how many were
suppressed.

## Inspecting logs

```sh
noxctl logs
noxctl logs --follow
noxctl logs --provider hyprland
```

The command uses the fixed `/usr/bin/journalctl` executable and scopes queries
to the user `noxd.service` unit. Provider names are validated identifiers; no
shell fragments are evaluated.

Equivalent direct inspection is:

```sh
journalctl --user -u noxd.service --no-pager
```

The service is configured with `StandardOutput=journal`,
`StandardError=journal`, and `SyslogIdentifier=noxd`, and retains
`Restart=on-failure` for clean user-session recovery.
