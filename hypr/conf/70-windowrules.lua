local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")
local rule = ctx.rule

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
  name = "sidepanel-default",
  match = { class = "^(noxflow%-sidepanel)$" },
  workspace = "special:sidepanel silent",
  float = true,
  size = "34% 92%",
  move = "65% 4%",
  rounding = 18,
  animation = "slide",
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
