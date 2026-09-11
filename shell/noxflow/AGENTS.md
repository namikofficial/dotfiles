# NoxFlow shell guidance

NoxFlow is the primary Quickshell desktop shell. `shell.qml` wires the surfaces;
`PanelController` owns major-panel selection and `MorphSurface` is the single
major-panel layer-shell window. Shared primitives live in `components/`, theme
tokens in `theme/`, and IPC clients call the `noxd` Unix socket.

After QML changes, run:

```sh
systemctl --user restart noxflow-shell.service
journalctl --user -u noxflow-shell --no-pager
tests/smoke/test-noxflow-surfaces.sh
```

The shell must compile with zero errors and warnings. A first-run
`FileView: file does not exist` warning is the only known benign exception.
Do not start Wayle alongside NoxFlow.
