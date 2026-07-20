assert(NOX_HYPR, "NOX_HYPR context missing")

-- A cinematic motion system: springy entrances, snappy exits, and a deeper
-- workspace glide. The child animations below keep opening, closing, moving,
-- and switching focus from collapsing into one generic effect.
hl.curve("windowIn", { type = "spring", mass = 1, stiffness = 170, dampening = 17 })
hl.curve("windowOut", { type = "bezier", points = { { 0.70, 0.0 }, { 0.84, 0.0 } } })
hl.curve("windowMove", { type = "spring", mass = 1, stiffness = 125, dampening = 18 })
hl.curve("layerIn", { type = "spring", mass = 1, stiffness = 210, dampening = 20 })
hl.curve("layerOut", { type = "bezier", points = { { 0.65, 0.0 }, { 0.90, 0.0 } } })
hl.curve("ui", { type = "bezier", points = { { 0.22, 0.90 }, { 0.18, 1.0 } } })
hl.curve("workspaceFlow", { type = "spring", mass = 1, stiffness = 105, dampening = 16 })
hl.curve("workspaceExit", { type = "bezier", points = { { 0.55, 0.0 }, { 0.90, 0.0 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "windowIn", style = "popin 86%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "windowIn", style = "popin 82%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "windowOut", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, spring = "windowMove" })
hl.animation({ leaf = "layers", enabled = true, speed = 7, spring = "layerIn", style = "popin 84%" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 7, spring = "layerIn", style = "popin 78%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 5, bezier = "layerOut", style = "fade" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "ui" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 7, bezier = "windowIn" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 5, bezier = "windowOut" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 3, bezier = "ui" })
hl.animation({ leaf = "border", enabled = true, speed = 12, bezier = "ui" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 10, bezier = "workspaceFlow" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "workspaceFlow", style = "slidefade 28%" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 7, bezier = "workspaceFlow", style = "slidefade 28%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 5, bezier = "workspaceExit", style = "slidefade 28%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 8, bezier = "windowIn", style = "slidefadevert 28%" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 8, bezier = "windowIn", style = "slidefadevert 34%" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 6, bezier = "workspaceExit", style = "slidefadevert 34%" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 6, bezier = "ui" })

hl.on("hyprland.start", function()
  hl.exec_cmd(string.format(
    "sh -lc %q",
    'nohup "$HOME/.config/hypr/scripts/session-critical.sh" >/dev/null 2>&1 &'
  ))
end)
