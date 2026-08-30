local M = {}

local uv = vim.uv

local function as_dir(path)
  if not path or path == "" then
    return vim.uv.cwd()
  end
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" and vim.fs.dirname(path) or path
end

function M.find_root(startpath, markers)
  local path = as_dir(startpath or vim.api.nvim_buf_get_name(0))
  return vim.fs.root(path, markers)
end

function M.project_root(startpath)
  return M.find_root(startpath, { ".git", "pnpm-workspace.yaml", "Cargo.toml", "package.json" }) or uv.cwd()
end

function M.buf_root(bufnr)
  return M.project_root(vim.api.nvim_buf_get_name(bufnr or 0))
end

return M
