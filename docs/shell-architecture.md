# NoxFlow shell architecture

```text
shell/noxflow/shell.qml
├── noxd provider models (signals/sockets, no per-second shell polling)
├── Bar.qml × active monitor
├── NoxIsland.qml × active monitor (coalesced OSD)
├── core/PanelController.qml (one major surface, explicit state)
├── core/MorphSurface.qml (one per-monitor animated PanelWindow + Loader)
├── Quick Settings (network, Bluetooth, audio, brightness, power sections)
├── Calendar / Notifications / Media (hosted content views)
└── config/{ShellConfig,Metrics,Motion}.qml (shared tokens)
```

`PanelController` is the single owner of major-panel selection. Registration
is per monitor; opening a panel selects the active monitor's `MorphSurface`,
closes any pending view, and records `activePanel`, `previousPanel`,
`targetMonitor`, `state`, and animation/interactivity flags.

`MorphSurface` is the only major-panel layer-shell window. It animates its
top/right origin, width, and height from the triggering bar chip to the target
panel rectangle. During switching, the old Loader content remains mounted
until the geometry is halfway through its transition, then the new content is
loaded into the same window. This prevents separate-window flashes and stale
input surfaces.

The hosted views retain only their internal content/focus transitions; panel
geometry and layer-shell ownership belong to `MorphSurface`. `MorphRegistry`
provides the triggering chip geometry and is intentionally not used for small
OSD updates.

Wayle is fallback-only. `panel-switch.sh` selects NoxFlow by default and stops
the other shell before starting either engine.
