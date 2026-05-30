local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")

hl.curve("enter", { type = "bezier", points = { { 0.18, 0.96 }, { 0.14, 1.0 } } })
hl.curve("exit", { type = "bezier", points = { { 0.36, 0.04 }, { 0.22, 1.0 } } })
hl.curve("ui", { type = "bezier", points = { { 0.20, 0.90 }, { 0.12, 1.0 } } })
hl.curve("workspaceFlow", { type = "bezier", points = { { 0.12, 0.98 }, { 0.08, 1.0 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "enter", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "exit", style = "popin 88%" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "ui" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "ui" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "ui" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "workspaceFlow", style = "slidefade 12%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 6, bezier = "enter", style = "slidefadevert 10%" })

hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm finalize")
  hl.exec_cmd(ctx.home .. "/.config/hypr/scripts/startup.sh")
end)
