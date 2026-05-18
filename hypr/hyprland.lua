-- Hyprland 0.55+ config.

local home = os.getenv("HOME") or ""
local source = debug.getinfo(1, "S").source
local config_dir = home .. "/.config/hypr"
if source:sub(1, 1) == "@" then
  config_dir = source:sub(2):match("(.+)/[^/]+$") or config_dir
end
local nx = dofile(config_dir .. "/lib/noxflow.lua")

local include = nx.include
local bind = nx.bind
local exec = nx.exec
local workspace = nx.workspace
local move_workspace = nx.move_workspace
local rule = nx.rule

local terminal = "kitty"
local fileManager = "dolphin"
local browser = "google-chrome-stable"
local menu = home .. "/.config/hypr/scripts/desktop-palette.sh"
local overview = home .. "/.config/hypr/scripts/workspace-overview.sh"
local mainMod = "SUPER"

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 8,
    border_size = 2,
    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
    col = {
      active_border = {
        colors = { "rgba(6f94c9ff)", "rgba(66c2b8ff)" },
        angle = 45,
      },
      inactive_border = "rgba(3f465fcc)",
    },
  },
  decoration = {
    rounding = 14,
    rounding_power = 2,
    active_opacity = 1.0,
    inactive_opacity = 0.96,
    dim_inactive = false,
    dim_strength = 0.04,
    shadow = {
      enabled = true,
      range = 16,
      render_power = 2,
      color = "rgba(00000066)",
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      vibrancy = 0.12,
    },
  },
  dwindle = {
    preserve_split = true,
  },
  master = {
    mfact = 0.60,
    new_status = "slave",
    new_on_top = true,
    new_on_active = "after",
    orientation = "left",
  },
  misc = {
    force_default_wallpaper = -1,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    vrr = 0,
  },
  cursor = {
    no_hardware_cursors = false,
  },
  input = {
    kb_layout = "us",
    follow_mouse = 1,
    sensitivity = 0,
    accel_profile = "adaptive",
    natural_scroll = false,
    touchpad = {
      natural_scroll = true,
      tap_to_click = true,
      drag_lock = true,
      scroll_factor = 0.95,
    },
  },
})

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
  hl.exec_cmd(home .. "/.config/hypr/scripts/startup.sh")
end)

-- Launch / session
exec(mainMod .. " + Return", terminal)
exec(mainMod .. " + E", fileManager)
exec(mainMod .. " + Space", menu)
exec(mainMod .. " + SHIFT + Space", home .. "/.config/hypr/scripts/launcher.sh --fast")
exec(mainMod .. " + CTRL + Space", overview)
exec(mainMod .. " + F1", home .. "/.config/hypr/scripts/hypr-binds.sh")
exec(mainMod .. " + Slash", menu)
exec(mainMod .. " + CTRL + Slash", home .. "/.config/hypr/scripts/hypr-binds.sh")
exec(mainMod .. " + A", menu)
exec(mainMod .. " + Y", overview)
exec(mainMod .. " + SHIFT + Y", home .. "/.config/hypr/scripts/panel-switch.sh toggle-view")
exec(mainMod .. " + CTRL + Y", home .. "/.config/hypr/scripts/panel-switch.sh wayle")
exec(mainMod .. " + CTRL + ALT + Y", home .. "/.config/hypr/scripts/panel-switch.sh toggle")
exec(mainMod .. " + CTRL + SHIFT + Y", home .. "/.config/hypr/scripts/theme-pass.sh")
exec(mainMod .. " + D", menu)
exec(mainMod .. " + comma", home .. "/.config/hypr/scripts/settings-hub.sh")
exec(mainMod .. " + SHIFT + comma", home .. "/.config/hypr/scripts/minimize-window.sh restore")
exec(mainMod .. " + CTRL + comma", home .. "/.config/hypr/scripts/settings-hub.sh quick")
exec(mainMod .. " + ALT + comma", home .. "/.config/hypr/scripts/settings/editor.sh")
exec(mainMod .. " + CTRL + ALT + comma", home .. "/.config/hypr/scripts/app-routing-apply-focused.sh")
exec(mainMod .. " + B", browser .. " --ozone-platform-hint=auto")
exec(mainMod .. " + G", home .. "/.config/hypr/scripts/layout-switcher.sh cycle")
exec(mainMod .. " + ALT + G", home .. "/.config/hypr/scripts/layout-switcher.sh toggle")
exec(mainMod .. " + P", home .. "/.config/hypr/scripts/monitor-control.sh menu")
exec(mainMod .. " + H", home .. "/.local/bin/hypr-phone menu")
exec(mainMod .. " + SHIFT + H", home .. "/.local/bin/hypr-phone mirror --profile default")
exec(mainMod .. " + CTRL + H", home .. "/.config/hypr/scripts/syncthing-control.sh open-ui")
bind(mainMod .. " + ALT + H", hl.dsp.exec_cmd("hyprctl dispatch togglespecialworkspace phone"))
exec(mainMod .. " + Escape", home .. "/.config/hypr/scripts/power-menu.sh")
exec(mainMod .. " + CTRL + L", home .. "/.config/hypr/scripts/lock.sh")
exec(mainMod .. " + CTRL + ALT + L", home .. "/.config/hypr/scripts/screensaver-awake.sh")
exec(mainMod .. " + backslash", home .. "/.config/hypr/scripts/sidepanel.sh toggle")
exec(mainMod .. " + SHIFT + backslash", home .. "/.config/hypr/scripts/sidepanel.sh send")
exec(mainMod .. " + CTRL + backslash", home .. "/.config/hypr/scripts/sidepanel.sh stash")
exec(mainMod .. " + S", home .. "/.config/hypr/scripts/scratchpad-manager.sh menu")
exec(mainMod .. " + CTRL + S", home .. "/.config/hypr/scripts/scratchpad-manager.sh launch logs")
exec(mainMod .. " + ALT + S", home .. "/.config/hypr/scripts/scratchpad-manager.sh launch ai")
exec(mainMod .. " + CTRL + ALT + S", home .. "/.config/hypr/scripts/scratchpad-manager.sh launch db")
exec(mainMod .. " + ALT + O", home .. "/.config/hypr/scripts/scratchpad-manager.sh launch obsidian")
exec(mainMod .. " + W", overview)
exec(mainMod .. " + tab", home .. "/.config/hypr/scripts/super-tab-overview.sh")
exec(mainMod .. " + SHIFT + tab", overview)
exec(mainMod .. " + O", home .. "/.config/hypr/scripts/set-wallpaper.sh --pick")
exec(mainMod .. " + SHIFT + O", home .. "/.config/hypr/scripts/set-wallpaper.sh --next")
exec(mainMod .. " + N", home .. "/.config/hypr/scripts/notif-center-toggle.sh")
exec(mainMod .. " + ALT + N", home .. "/.config/hypr/scripts/notif-dnd-toggle.sh")
exec(mainMod .. " + CTRL + N", home .. "/.config/hypr/scripts/notification-summary.sh copy")
exec(mainMod .. " + CTRL + ALT + N", home .. "/.config/hypr/scripts/notif-clear.sh")
exec(mainMod .. " + SHIFT + N", home .. "/.config/hypr/scripts/open-notes.sh")
exec(mainMod .. " + ALT + E", home .. "/.config/hypr/scripts/open-notes.sh")
bind(mainMod .. " + SHIFT + Q", hl.dsp.window.kill())
exec(mainMod .. " + SHIFT + M", home .. "/.config/hypr/scripts/minimize-window.sh minimize")
exec(mainMod .. " + F", home .. "/.config/hypr/scripts/float-toggle-smart.sh")
bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
exec(mainMod .. " + V", home .. "/.config/hypr/scripts/float-toggle-smart.sh")
bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo())
bind(mainMod .. " + C", hl.dsp.window.center())

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

exec(mainMod .. " + SHIFT + left", "hyprctl dispatch movewindow l")
exec(mainMod .. " + SHIFT + right", "hyprctl dispatch movewindow r")
exec(mainMod .. " + SHIFT + up", "hyprctl dispatch movewindow u")
exec(mainMod .. " + SHIFT + down", "hyprctl dispatch movewindow d")

bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ x = -80, y = 0 }))
bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ x = 80, y = 0 }))
bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ x = 0, y = -80 }))
bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ x = 0, y = 80 }))
bind(mainMod .. " + CTRL + SHIFT + left", hl.dsp.window.resize({ x = -80, y = 0 }))
bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.window.resize({ x = 80, y = 0 }))
bind(mainMod .. " + CTRL + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -80 }))
bind(mainMod .. " + CTRL + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 80 }))

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

-- Window rules
rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

rule({
  name = "float-settings",
  match = { class = "^(pavucontrol|blueman-manager|nm-connection-editor|nm-applet|rofi|wlogout)$" },
  float = true,
})

rule({
  name = "clipboard-browser-float",
  match = { class = "^(dev.noxflow.ClipboardBrowser)$" },
  float = true,
  size = "76% 82%",
  center = true,
  rounding = 20,
  animation = "popin 92%",
})

rule({
  name = "rofi-motion",
  match = { class = "^(rofi)$" },
  animation = "popin 88%",
})

rule({
  name = "wlogout-motion",
  match = { class = "^(wlogout)$" },
  animation = "popin 92%",
})

rule({
  name = "utility-motion",
  match = { class = "^(pavucontrol|blueman-manager|nm-connection-editor|nm-applet)$" },
  animation = "popin 90%",
})

rule({
  name = "move-hyprland-run",
  match = { class = "^hyprland%-run$" },
  move = { 20, "monitor_h-120" },
  float = true,
})

rule({
  name = "logs-workspace",
  match = { class = "^(noxflow%-logs)$" },
  workspace = "9",
})

rule({
  name = "telemetry-workspace",
  match = { class = "^(noxflow%-telemetry)$" },
  workspace = "10",
})

rule({
  name = "hypr-phone-special",
  match = { title = "^(hypr-phone:.*)$" },
  workspace = "special:phone silent",
  float = true,
  size = "420 900",
  center = true,
})

rule({
  name = "calm-empty-xwayland-popups",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_initial_focus = true,
  border_size = 0,
  rounding = 0,
  animation = "none",
})

rule({
  name = "android-studio-main-stability",
  match = { class = "^(jetbrains%-studio|Android%-studio|android%-studio)$" },
  opacity = "1.0 1.0",
  border_size = 0,
  animation = "none",
})

rule({
  name = "android-studio-popup-stability",
  match = {
    class = "^(jetbrains%-studio|Android%-studio|android%-studio)$",
    float = true,
    fullscreen = false,
  },
  border_size = 0,
  rounding = 0,
  animation = "none",
})

rule({
  name = "vscode-glass",
  match = { class = "^(code|Code|code%-url%-handler)$" },
  opacity = "0.96 0.9",
})

rule({
  name = "prism-glass",
  match = { class = "^(org%.prismlauncher%.PrismLauncher|prismlauncher|PrismLauncher)$" },
  opacity = "0.98 0.93",
})

rule({
  name = "obsidian-glass",
  match = { class = "^(obsidian|Obsidian)$" },
  opacity = "0.96 0.9",
})

rule({
  name = "tmux-scratch-quake",
  match = { class = "^(noxflow%-tmux%-scratch)$" },
  workspace = "special:scratch_tmux silent",
  float = true,
  size = "80% 45%",
  move = { "10%", 70 },
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-dashboard",
  match = { title = "^(Spatial Scratchpad)$" },
  float = true,
  center = true,
  rounding = 18,
  animation = "popin 88%",
  opacity = "0.98 0.96",
})

rule({
  name = "scratch-terminal",
  match = { class = "^(noxflow%-scratch%-terminal)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "64% 36%",
  move = "0% 0%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-music",
  match = { class = "^(noxflow%-scratch%-music)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "30% 100%",
  move = "0% 0%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-notes",
  match = { class = "^(noxflow%-scratch%-notes)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "32% 36%",
  move = "0% 36%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-db",
  match = { class = "^(noxflow%-scratch%-db)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "32% 36%",
  move = "32% 36%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-ai",
  match = { class = "^(noxflow%-scratch%-ai)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "36% 72%",
  move = "64% 0%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-logs",
  match = { class = "^(noxflow%-scratch%-logs)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "100% 28%",
  move = "0% 72%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "scratch-browser",
  match = { class = "^(noxflow%-scratch%-browser)$" },
  workspace = "special:scratch_spatial silent",
  float = true,
  size = "60% 68%",
  move = "4% 4%",
  rounding = 18,
  animation = "popin",
})

rule({
  name = "tmux-projects-float",
  match = { class = "^(noxflow%-tmux%-projects)$" },
  float = true,
  size = "65% 62%",
  center = true,
})

rule({
  name = "lazygit-float",
  match = { class = "^(noxflow%-lazygit)$" },
  float = true,
  size = "90% 90%",
  center = true,
})

rule({
  name = "tool-large-float",
  match = { class = "^(noxflow%-tool%-large)$" },
  float = true,
  size = "82% 82%",
  center = true,
})

rule({
  name = "tool-small-float",
  match = { class = "^(noxflow%-tool%-small)$" },
  float = true,
  size = "48% 55%",
  center = true,
})

include(home .. "/.cache/hypr/theme-colors-hyprland.lua")
include(home .. "/.cache/hypr/settings.generated.lua")
