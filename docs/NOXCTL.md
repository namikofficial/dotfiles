# `noxctl` command reference

`noxctl` is the supported command-line client for the NoxFlow daemon. It uses
versioned newline-delimited JSON over the private Unix socket; it never
evaluates user input as a shell command.

Global options:

```sh
noxctl --help
noxctl --json status
noxctl --socket "$XDG_RUNTIME_DIR/noxflow/noxd.sock" --timeout-ms 1000 status
```

Useful examples:

```sh
noxctl status
noxctl provider status audio
noxctl audio volume +5
noxctl brightness set 70
noxctl network wifi enable
noxctl bluetooth connect AA:BB:CC:DD:EE:FF
noxctl media play-pause
noxctl profile list
noxctl config --profile focus
noxctl doctor
noxctl doctor --full
noxctl shell use noxflow
noxctl shell use wayle
noxctl shell restart
noxctl shell safe-mode
```

Use `--json` for automation. JSON output contains command data rather than
the underlying IPC envelope:

```sh
noxctl --json provider status audio
```

Exit codes are stable: `0` means success, `1` means daemon/IPC/provider or
local operational failure, `2` means invalid arguments, and `3` means the
daemon and client do not share a protocol version. Socket connection,
read/write, and response handling are bounded by a two-second default timeout.

The CLI reports daemon errors on stderr and includes the socket path for
connection failures. Override the timeout with `--timeout-ms` when diagnosing
an unusually slow session.

## Shell completion

Generate completion scripts directly from the command definition:

```sh
noxctl completions zsh > "${ZDOTDIR:-$HOME}/.zfunc/_noxctl"
noxctl completions bash > ~/.local/share/bash-completion/completions/noxctl
noxctl completions fish > ~/.config/fish/completions/noxctl.fish
```

The `shell` group exposes only fixed NoxFlow session operations such as
`shell use`, `shell restart`, and `shell toggle`; it does not accept arbitrary
programs or command strings.
