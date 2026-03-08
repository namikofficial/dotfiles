local M = {}

local uv = vim.uv or vim.loop

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" or false
end

local function join(...)
  return table.concat({ ... }, "/")
end

function M.find_root(startpath, markers)
  local path = startpath
  if path == "" then
    return nil
  end

  if is_file(path) then
    path = vim.fs.dirname(path)
  end

  local found = vim.fs.find(markers, {
    path = path,
    upward = true,
    stop = vim.loop.os_homedir(),
  })[1]

  return found and vim.fs.dirname(found) or nil
end

function M.noxflow_root(startpath)
  return M.find_root(startpath or vim.api.nvim_buf_get_name(0), {
    "pnpm-workspace.yaml",
    "turbo.json",
    ".git",
  })
end

function M.is_noxflow_repo(startpath)
  local root = M.noxflow_root(startpath)
  return root ~= nil and root:match("/noxflow$") ~= nil
end

function M.nearest_workspace_dir(startpath)
  local path = startpath or vim.api.nvim_buf_get_name(0)
  local root = M.noxflow_root(path)
  if not root then
    return nil
  end

  local found = vim.fs.find({ "package.json", "Cargo.toml" }, {
    path = path,
    upward = true,
    stop = root,
  })[1]

  return found and vim.fs.dirname(found) or root
end

function M.read_json(path)
  if not is_file(path) then
    return nil
  end

  local lines = vim.fn.readfile(path)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then
    return nil
  end
  return decoded
end

function M.nearest_package(startpath)
  local dir = M.nearest_workspace_dir(startpath)
  if not dir then
    return nil
  end

  local package_json = join(dir, "package.json")
  local data = M.read_json(package_json)
  if not data then
    return nil
  end

  return {
    dir = dir,
    name = data.name,
    scripts = data.scripts or {},
  }
end

function M.open_terminal(command, opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.loop.cwd()
  local label = opts.label or command

  vim.cmd("botright 14split")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buflisted = false
  vim.fn.termopen(command, {
    cwd = cwd,
  })
  vim.cmd("startinsert")
  pcall(vim.api.nvim_buf_set_name, buf, "term://" .. label)
end

function M.telescope_find_in_dir(prompt_title, cwd)
  require("telescope.builtin").find_files({
    cwd = cwd,
    prompt_title = prompt_title,
    hidden = true,
  })
end

function M.telescope_grep_in_dir(prompt_title, cwd)
  require("telescope.builtin").live_grep({
    cwd = cwd,
    prompt_title = prompt_title,
  })
end

return M
