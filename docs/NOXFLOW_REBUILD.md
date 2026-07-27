# NoxFlow rebuild

This repository is migrating from a Wayle-first desktop to a layered NoxFlow
shell. Wayle remains the fallback while the new shell is developed.

## Current foundation

- `core/noxd`: std-only daemon with a versioned status response over an XDG
  runtime Unix socket.
- `cli/noxctl`: status, doctor, and shell switching entry points.
- `shell/noxflow`: Quickshell development diagnostics surface and reusable
  asynchronous noxd IPC client; it contains no production bar yet.
- `theme/tokens.toml`: canonical Material design-token source.
- `shell/noxflow/theme/Tokens.qml`: generated QML token singleton consumed by
  shell primitives.
- `shell/noxflow/components`: reusable token-driven Material primitives.
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

## Material design system

Validate and regenerate the QML token export after editing the canonical TOML:

```sh
python3 setup/generate-material-tokens.py
python3 setup/generate-material-tokens.py --check
python3 -m unittest tests/theme/test_tokens.py
```

The development surface opens on the component gallery. It includes token
swatches, all shared primitives, keyboard-focus and interaction states, density
controls, reduced-motion controls, and the existing noxd provider diagnostics.
