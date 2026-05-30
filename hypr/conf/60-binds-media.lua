local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")
local bind = ctx.bind
local exec = ctx.exec
local home = ctx.home
local mainMod = ctx.mainMod

-- Clipboard / screenshots
exec(mainMod .. " + CTRL + V", home .. "/.config/hypr/scripts/cliphist-rofi.sh")
exec(mainMod .. " + SHIFT + V", home .. "/.config/hypr/scripts/cliphist-toggle.sh")
exec(mainMod .. " + SHIFT + S", home .. "/.config/hypr/scripts/screenshot.sh area")
exec(mainMod .. " + CTRL + SHIFT + S", home .. "/.config/hypr/scripts/screenshot.sh full")
exec(mainMod .. " + SHIFT + T", home .. "/.config/hypr/scripts/ocr-capture.sh")
exec(mainMod .. " + SHIFT + C", "kage ai commit-msg")
exec(mainMod .. " + SHIFT + R", "kage ai review")
exec(mainMod .. " + SHIFT + E", "kage ai explain")
exec(mainMod .. " + CTRL + R", home .. "/.config/hypr/scripts/screen-record-toggle.sh")
bind(mainMod .. " + I", hl.dsp.exec_cmd("hyprpicker -a"))
exec(mainMod .. " + SHIFT + I", home .. "/.config/hypr/scripts/night-light-toggle.sh")
exec("XF86Launch2", home .. "/.config/hypr/scripts/ai-helper.sh ask")
exec("XF86Launch3", home .. "/.config/hypr/scripts/ai-helper.sh clip")
exec("XF86Launch4", home .. "/.config/hypr/scripts/ai-helper.sh shell")
exec("XF86Launch5", home .. "/.config/hypr/scripts/ai-helper.sh debug")
exec(mainMod .. " + ALT + 2", home .. "/.config/hypr/scripts/ai-helper.sh raw")
exec(mainMod .. " + ALT + 3", home .. "/.config/hypr/scripts/ai-helper.sh clip")
exec(mainMod .. " + ALT + 4", home .. "/.config/hypr/scripts/ai-helper.sh shell")
exec(mainMod .. " + ALT + 5", home .. "/.config/hypr/scripts/ai-helper.sh debug")

-- Mouse drag actions
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media keys
exec("XF86AudioRaiseVolume", home .. "/.config/hypr/scripts/volume-control.sh up", { locked = true, repeating = true })
exec("XF86AudioLowerVolume", home .. "/.config/hypr/scripts/volume-control.sh down", { locked = true, repeating = true })
exec("XF86AudioMute", home .. "/.config/hypr/scripts/volume-control.sh mute", { locked = true, repeating = true })
exec("XF86AudioMicMute", home .. "/.config/hypr/scripts/volume-control.sh mic-mute", { locked = true, repeating = true })
exec("XF86MonBrightnessUp", home .. "/.config/hypr/scripts/brightness-control.sh up", { locked = true, repeating = true })
exec("XF86MonBrightnessDown", home .. "/.config/hypr/scripts/brightness-control.sh down", { locked = true, repeating = true })
exec("XF86AudioNext", home .. "/.config/hypr/scripts/media-control.sh next", { locked = true })
exec("XF86AudioPause", home .. "/.config/hypr/scripts/media-control.sh play-pause", { locked = true })
exec("XF86AudioPlay", home .. "/.config/hypr/scripts/media-control.sh play-pause", { locked = true })
exec("XF86AudioPrev", home .. "/.config/hypr/scripts/media-control.sh previous", { locked = true })
