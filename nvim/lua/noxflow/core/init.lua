require("noxflow.core.options")
require("noxflow.core.keymaps")
require("noxflow.core.autocmds")

-- The wallpaper pipeline writes a small Lua adapter instead of mutating this
-- config. Re-apply it after a colorscheme load and when the file changes.
local function apply_runtime_theme()
  local path = vim.fn.expand("~/.cache/hypr/theme-nvim.lua")
  if vim.fn.filereadable(path) ~= 1 then
    return
  end
  local ok, palette = pcall(dofile, path)
  if not ok or type(palette) ~= "table" then
    return
  end
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
