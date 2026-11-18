local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")
local exec = ctx.exec
local home = ctx.home
local mainMod = ctx.mainMod

-- Nox Atlas owns the window/workspace overview. Keeping the bind in Hyprland
-- preserves the compositor-level shortcut while the shell owns presentation,
-- keyboard selection, focus, and drag-to-move.
exec(mainMod .. " + Tab", home .. "/.local/bin/noxctl panel toggle atlas")
