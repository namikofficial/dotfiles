# NoxFlow rebuild

This repository is migrating from a Wayle-first desktop to a layered NoxFlow
shell. Wayle remains the fallback while the new shell is developed.

## Current foundation

- `core/noxd`: std-only daemon with a versioned status response over an XDG
  runtime Unix socket.
- `cli/noxctl`: status, doctor, and shell switching entry points.
- `shell/noxflow`: first Material-style test surface with no embedded commands.
- `theme/tokens.toml`: shared semantic design tokens.
- `config/default.toml`: shell and IPC defaults.

Build the binaries and place them in `~/.local/bin` before enabling the user
unit. The unit is intentionally not linked or enabled by bootstrap yet.

