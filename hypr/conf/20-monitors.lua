local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")

-- Do not bind the shell to a connector name. monitor-control.sh applies the
-- user's persisted laptop/external layout after startup and can choose the
-- correct per-monitor scale.
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = 1,
})
