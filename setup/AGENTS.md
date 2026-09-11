# Setup and shell-script guidance

`setup/` owns bootstrap, installation, health, and verification control planes.
Scripts must be non-interactive, fail fast, preserve user state, and avoid
destructive cleanup or credential access unless explicitly requested.

After shell-script changes run:

```sh
./setup/check-shell.sh --all
```

For generated keybind documentation run
`./setup/generate-keybind-docs.py` followed by
`./setup/check-keybind-docs.sh`. Prefer reversible backups and exact paths in
link/installer scripts.
