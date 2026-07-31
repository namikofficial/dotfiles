local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")
local bind = ctx.bind
local exec = ctx.exec
local home = ctx.home
local mainMod = ctx.mainMod

-- hyprland-scroll-overview — primary window/workspace navigator.
-- Replaces the QML Overview (deleted 2026-07-31). ABI-breaking plugin:
-- rebuild after every Hyprland upgrade (see docs/shell-redesign/02-reference-analysis.md
-- and setup/scrolloverview-rebuild.sh).
--
-- NOTE: hl.plugin.scrolloverview is only defined when the plugin is loaded.
-- Guard every reference so a config reload without the plugin degrades
-- gracefully (falls back to the legacy workspace-overview script).

-- Detect the plugin without throwing when it is absent.
local ok, scroll = pcall(function() return hl.plugin and hl.plugin.scrolloverview end)
if not ok then scroll = nil end

-- Plugin configuration (Lua form; shadow.color must be an integer, not rgba()).
-- IMPORTANT: only apply when the plugin is actually loaded. hl.config validates
-- keys against the known config schema, so setting plugin.scrolloverview.* while
-- the plugin is absent produces "unknown config key" errors on every reload.
if scroll then
  hl.config({
    plugin = {
      scrolloverview = {
        gesture_distance = 300,
        scale = 0.56,
        workspace_gap = 72,
        layout = "horizontal",
        wallpaper = 0,
        blur = false,
        input = {
          scroll_event_delay = 140,
          touchpad_scroll_factor = 1.0,
          scrolling_mode = 0,
          drag_mode = 0,
          drag_threshold = 10,
        },
        shadow = {
          enabled = true,
          range = 24,
          render_power = 3,
          color = 0x66000000,
        },
      },
    },
  })

  -- Trackpad gesture: 3-finger up opens the overview.
  scroll.gesture({ fingers = 3, direction = "vertical" })

  -- SUPER+TAB toggles the overview.
  bind(mainMod .. " + Tab", function()
    scroll.overview("toggle")
  end)

  -- Keyboard-complete navigation submap (replaces built-in navigation while
  -- active). Universal workspace binds survive via submap_universal.
  hl.define_submap("scrolloverview", function()
    bind("left", scroll.navigate("left"))
    bind("right", scroll.navigate("right"))
    bind("up", scroll.navigate("up"))
    bind("down", scroll.navigate("down"))
    bind("h", scroll.navigate("left"))
    bind("l", scroll.navigate("right"))
    bind("k", scroll.navigate("up"))
    bind("j", scroll.navigate("down"))
    bind("return", scroll.overview("select"))
    bind("space", scroll.overview("select"))
    bind("escape", scroll.overview("off"))
    bind("mouse:272", function()
      scroll.overview("select")
      scroll.window("select")
      scroll.overview("off")
    end, { mouse = true })
    bind("mouse:274", scroll.window("close"), { mouse = true })
  end)
else
  -- Plugin not loaded: SUPER+TAB falls back to the legacy script.
  exec(mainMod .. " + Tab", home .. "/.config/hypr/scripts/super-tab-overview.sh")
end
