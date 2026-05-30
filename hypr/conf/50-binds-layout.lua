local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")
local bind = ctx.bind
local exec = ctx.exec
local home = ctx.home
local mainMod = ctx.mainMod
local move_workspace = ctx.move_workspace
local workspace = ctx.workspace

-- Tiling helpers
bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
bind(mainMod .. " + ALT + J", hl.dsp.layout("orientationcycle left top right bottom"))
bind(mainMod .. " + K", hl.dsp.layout("swapsplit"))
bind(mainMod .. " + CTRL + Return", hl.dsp.layout("swapwithmaster master"))
exec(mainMod .. " + SHIFT + G", home .. "/.config/hypr/scripts/layout-switcher.sh allfloat")
exec(mainMod .. " + CTRL + G", home .. "/.config/hypr/scripts/layout-switcher.sh master")
exec(mainMod .. " + CTRL + SHIFT + G", home .. "/.config/hypr/scripts/layout-switcher.sh dwindle")
exec(mainMod .. " + CTRL + ALT + G", home .. "/.config/hypr/scripts/layout-switcher.sh scroll")
exec(mainMod .. " + CTRL + ALT + SHIFT + G", home .. "/.config/hypr/scripts/layout-switcher.sh monocle")
exec(mainMod .. " + ALT + F", home .. "/.config/hypr/scripts/layout-switcher.sh allfloat")
exec(mainMod .. " + CTRL + ALT + P", home .. "/.config/hypr/scripts/layout-switcher.sh allpseudo")
bind(mainMod .. " + CTRL + ALT + left", hl.dsp.layout("mfact -0.04"))
bind(mainMod .. " + CTRL + ALT + right", hl.dsp.layout("mfact +0.04"))

bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

exec("ALT + tab", "hyprctl dispatch cyclenext && hyprctl dispatch bringactivetotop")
exec("ALT + SHIFT + tab", "hyprctl dispatch cyclenext prev && hyprctl dispatch bringactivetotop")

bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ relative = true, x = -80, y = 0 }))
bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ relative = true, x = 80, y = 0 }))
bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ relative = true, x = 0, y = -80 }))
bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ relative = true, x = 0, y = 80 }))
bind(mainMod .. " + CTRL + SHIFT + left", hl.dsp.window.resize({ relative = true, x = -80, y = 0 }))
bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.window.resize({ relative = true, x = 80, y = 0 }))
bind(mainMod .. " + CTRL + SHIFT + up", hl.dsp.window.resize({ relative = true, x = 0, y = -80 }))
bind(mainMod .. " + CTRL + SHIFT + down", hl.dsp.window.resize({ relative = true, x = 0, y = 80 }))

workspace(mainMod .. " + bracketleft", "e-1")
workspace(mainMod .. " + bracketright", "e+1")
move_workspace(mainMod .. " + SHIFT + bracketleft", "e-1")
move_workspace(mainMod .. " + SHIFT + bracketright", "e+1")

for i = 1, 10 do
  local key = i == 10 and "0" or tostring(i)
  workspace(mainMod .. " + " .. key, tostring(i))
  move_workspace(mainMod .. " + SHIFT + " .. key, tostring(i))
end

exec(mainMod .. " + CTRL + 0", home .. "/.config/hypr/scripts/telemetry-workspace.sh open")
exec(mainMod .. " + CTRL + SHIFT + 0", home .. "/.config/hypr/scripts/telemetry-workspace.sh reset")
exec(mainMod .. " + CTRL + 9", home .. "/.config/hypr/scripts/logs-workspace.sh open")
exec(mainMod .. " + CTRL + SHIFT + 9", home .. "/.config/hypr/scripts/logs-workspace.sh stack")

bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Window groups
bind(mainMod .. " + T", hl.dsp.group.toggle())
bind(mainMod .. " + CTRL + T", hl.dsp.window.move({ out_of_group = true }))
bind(mainMod .. " + ALT + period", hl.dsp.group.next())
bind(mainMod .. " + ALT + semicolon", hl.dsp.group.prev())
exec(mainMod .. " + period", home .. "/.config/hypr/scripts/dev-cheatsheet.sh")
