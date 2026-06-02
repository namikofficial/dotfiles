local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")

hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "0x0",
  scale = 1,
})

hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto-up",
  scale = 1,
})
