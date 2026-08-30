# Shell rollback

This work is isolated in the working tree because the sandbox could not create
a Git ref under `.git`. Before applying it outside the workspace, create a
branch or commit the current tree:

```sh
git switch -c shell-redesign-rollback-point
git add -A && git commit -m 'checkpoint before shell redesign'
```

To return to the previous shell without deleting files:

```sh
shellctl close || true
systemctl --user stop noxflow-shell.service
printf 'wayle\n' > "${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/panel.engine"
systemctl --user start wayle.service
```

To restore this implementation, run `setup/install-noxflow-foundation.sh` or
`setup/bootstrap-noxflow.sh`, then:

```sh
shellctl reload
```

No destructive cleanup is required; the legacy Wayle configuration remains
available for recovery.
