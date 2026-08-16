local ctx = assert(NOX_HYPR, "NOX_HYPR context missing")

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 2,
    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
    col = {
      active_border = {
        colors = { "rgba(00e5ffff)", "rgba(ff3cacff)" },
        angle = 45,
      },
      inactive_border = "rgba(40205fcc)",
    },
  },
  decoration = {
    rounding = 12,
    rounding_power = 2,
    active_opacity = 0.94,
    inactive_opacity = 0.88,
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
      size = 2,
      passes = 2,
      vibrancy = 0.24,
    },
    motion_blur = {
      enabled = true,
      samples = 8,
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
