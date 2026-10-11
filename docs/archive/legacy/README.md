# Legacy desktop components

The existing Wayle, Rofi, GTK and helper-script stack remains in its original
locations during the NoxFlow migration. Do not remove or move those components
until the replacement surface has feature parity and the fallback path has been
tested through a real login.

The first migration slice is additive: `shell/noxflow`, `core/noxd`, `cli/noxctl`,
`config`, `theme`, and `systemd/user/noxd.service` are the new foundation.

