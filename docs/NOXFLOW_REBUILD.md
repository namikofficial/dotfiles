# NoxFlow rebuild

This repository is migrating from a Wayle-first desktop to a layered NoxFlow
shell. Wayle remains the fallback while the new shell is developed.

## Current foundation

- `core/noxd`: std-only daemon with a versioned status response over an XDG
  runtime Unix socket.
- `cli/noxctl`: status, doctor, and shell switching entry points.
- `shell/noxflow`: Quickshell development diagnostics surface and reusable
  asynchronous noxd IPC client; it contains no production bar yet.
- `theme/tokens.toml`: shared semantic design tokens.
- `config/default.toml`: shell and IPC defaults.

Build the binaries and place them in `~/.local/bin` before enabling the user
unit. The unit is intentionally not linked or enabled by bootstrap yet.

## Quickshell IPC diagnostics

Install Quickshell, build and enable `noxd`, then launch the development
surface directly from this repository:

```sh
quickshell --path ./shell/noxflow
```

The surface negotiates protocol version 1, loads the initial provider state,
subscribes to events, and reconnects automatically when noxd restarts. The
client uses asynchronous Quickshell socket I/O, so socket operations do not
block the QML UI thread.
