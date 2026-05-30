-- Hyprland workstation entrypoint.
-- Keep this file stable; put feature-specific config in hypr/conf/*.lua.

local home = os.getenv("HOME") or ""
local source = debug.getinfo(1, "S").source
local source_path = source:sub(1, 1) == "@" and source:sub(2) or nil

local function dirname(path)
  return path and path:match("(.+)/[^/]+$") or nil
end

local function file_exists(path)
  local handle = io.open(path, "r")
  if not handle then
    return false
  end
  handle:close()
  return true
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

local function resolve_realpath(path)
  if not path or not io.popen then
    return nil
  end

  local handle = io.popen("readlink -f " .. shell_quote(path) .. " 2>/dev/null")
  if not handle then
    return nil
  end

  local resolved = handle:read("*l")
  handle:close()
  return resolved
end

local function choose_config_dir()
  local real_source_path = resolve_realpath(source_path)
  local default_dir = home .. "/.config/hypr"
  local candidates = {
    dirname(source_path),
    dirname(real_source_path),
    default_dir,
  }

  for _, candidate in ipairs(candidates) do
    if candidate and file_exists(candidate .. "/lib/noxflow.lua") and file_exists(candidate .. "/conf/10-general.lua") then
      return candidate
    end
  end

  for _, candidate in ipairs(candidates) do
    if candidate and file_exists(candidate .. "/lib/noxflow.lua") then
      return candidate
    end
  end

  return default_dir
end

local config_dir = choose_config_dir()

local nx = dofile(config_dir .. "/lib/noxflow.lua")

_G.NOX_HYPR = {
  home = home,
  config_dir = config_dir,
  include = nx.include,
  bind = nx.bind,
  exec = nx.exec,
  workspace = nx.workspace,
  move_workspace = nx.move_workspace,
  rule = nx.rule,
  terminal = "kitty",
  fileManager = "kitty --class yazi -e yazi",
  browser = "google-chrome-stable",
  menu = home .. "/.config/hypr/scripts/desktop-palette.sh",
  overview = home .. "/.config/hypr/scripts/workspace-overview.sh",
  mainMod = "SUPER",
}

for _, rel_path in ipairs({
  "conf/10-general.lua",
  "conf/20-monitors.lua",
  "conf/30-animations.lua",
  "conf/40-binds-launch.lua",
  "conf/50-binds-layout.lua",
  "conf/60-binds-media.lua",
  "conf/70-windowrules.lua",
  "conf/90-generated.lua",
}) do
  nx.include(config_dir .. "/" .. rel_path)
end

_G.NOX_HYPR = nil
