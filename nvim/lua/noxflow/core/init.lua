require("noxflow.core.options")
require("noxflow.core.keymaps")
require("noxflow.core.autocmds")
require("noxflow.core.sops")

-- The wallpaper pipeline (hypr/scripts/theme-sync.sh) writes
-- ~/.cache/hypr/theme-nvim.lua, which sets vim.g.noxflow_* and returns nothing.
-- Re-apply after a colorscheme load, and on focus/buffer change only when the
-- file's mtime moved.
local theme_path = vim.fn.expand("~/.cache/hypr/theme-nvim.lua")
local theme_applied_mtime = nil

local function read_runtime_palette()
  if not pcall(dofile, theme_path) then
    return nil
  end
  local g = vim.g
  if not (g.noxflow_text and g.noxflow_surface_canvas and g.noxflow_primary) then
    return nil
  end
  return {
    foreground = g.noxflow_text,
    background = g.noxflow_surface_canvas,
    surface = g.noxflow_surface1 or g.noxflow_surface,
    surface_alt = g.noxflow_surface2 or g.noxflow_surface,
    muted = g.noxflow_text_muted,
    -- Not noxflow_outline: that is ~#2a0300 on a ~#210c00 float, i.e.
    -- invisible borders. The float surface reads as a soft edge.
    outline = g.noxflow_surface_float or g.noxflow_outline_strong,
    primary = g.noxflow_primary,
    secondary = g.noxflow_secondary,
    success = g.noxflow_success,
    warning = g.noxflow_warning,
    danger = g.noxflow_danger,
  }
end

local function apply_runtime_theme(opts)
  local stat = vim.uv.fs_stat(theme_path)
  if not stat then
    return
  end
  local force = opts and opts.event == "ColorScheme"
  local mtime = stat.mtime.sec * 1e9 + stat.mtime.nsec
  if not force and theme_applied_mtime == mtime then
    return
  end
  local palette = read_runtime_palette()
  if not palette then
    return
  end
  theme_applied_mtime = mtime
  local groups = {
    Normal = { fg = palette.foreground, bg = palette.background },
    NormalFloat = { fg = palette.foreground, bg = palette.surface },
    FloatBorder = { fg = palette.outline, bg = palette.surface },
    WinSeparator = { fg = palette.outline, bg = palette.background },
    StatusLine = { fg = palette.foreground, bg = palette.surface },
    StatusLineNC = { fg = palette.muted, bg = palette.background },
    Pmenu = { fg = palette.foreground, bg = palette.surface },
    PmenuSel = { fg = palette.background, bg = palette.primary, bold = true },
    Visual = { bg = palette.surface_alt },
    Search = { fg = palette.background, bg = palette.warning, bold = true },
    IncSearch = { fg = palette.background, bg = palette.primary, bold = true },
    CursorLine = { bg = palette.surface },
    DiagnosticError = { fg = palette.danger },
    DiagnosticWarn = { fg = palette.warning },
    DiagnosticInfo = { fg = palette.secondary },
    DiagnosticOk = { fg = palette.success },
  }
  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

local runtime_theme_group = vim.api.nvim_create_augroup("noxflow_runtime_theme", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = runtime_theme_group,
  callback = apply_runtime_theme,
})
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  group = runtime_theme_group,
  callback = apply_runtime_theme,
})
vim.defer_fn(apply_runtime_theme, 0)
