#!/usr/bin/env bash
set -euo pipefail

config_file="${HYPR_CONF_PATH:-$HOME/.config/hypr/hyprland.lua}"
mode="menu"

usage() {
  cat <<'EOF'
Usage: hypr-binds.sh [--print] [--conf <path>]
  --print        Print parsed keybind table to stdout
  --conf <path>  Parse a specific hyprland.lua file
EOF
}

while (($#)); do
  case "$1" in
    --print)
      mode="print"
      ;;
    --conf)
      shift
      config_file="${1:-}"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

lua_bin=""
for candidate in lua luajit; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_bin="$(command -v "$candidate")"
    break
  fi
done

render_table_from_lua() {
  "$lua_bin" - "$config_file" <<'LUA'
local config_path = arg[1]
local binds = {}

local function dispatcher(kind, spec)
  if type(spec) == "table" then
    spec.__kind = kind
    return spec
  end
  return { __kind = kind, value = spec }
end

hl = {
  config = function() end,
  monitor = function() end,
  curve = function() end,
  animation = function() end,
  on = function() end,
  window_rule = function() end,
  bind = function(keys, dispatcher_value, opts)
    binds[#binds + 1] = { keys = keys, dispatcher = dispatcher_value, opts = opts or {} }
  end,
  dispatch = function() end,
  exec_cmd = function(cmd)
    return dispatcher("exec_cmd", { cmd = cmd })
  end,
  dsp = {
    exec_cmd = function(cmd)
      return dispatcher("exec_cmd", { cmd = cmd })
    end,
    layout = function(msg)
      return dispatcher("layout", { msg = msg })
    end,
    focus = function(spec)
      return dispatcher("focus", spec or {})
    end,
    exit = function()
      return dispatcher("exit", {})
    end,
    submap = function(name)
      return dispatcher("submap", { name = name })
    end,
    pass = function(spec)
      return dispatcher("pass", spec or {})
    end,
    send_shortcut = function(spec)
      return dispatcher("send_shortcut", spec or {})
    end,
    send_key_state = function(spec)
      return dispatcher("send_key_state", spec or {})
    end,
    dpms = function(spec)
      return dispatcher("dpms", spec or {})
    end,
    event = function(msg)
      return dispatcher("event", { msg = msg })
    end,
    global = function(msg)
      return dispatcher("global", { msg = msg })
    end,
    force_idle = function(seconds)
      return dispatcher("force_idle", { seconds = seconds })
    end,
    no_op = function()
      return dispatcher("no_op", {})
    end,
    window = {
      close = function() return dispatcher("window.close", {}) end,
      kill = function() return dispatcher("window.kill", {}) end,
      signal = function(spec) return dispatcher("window.signal", spec or {}) end,
      float = function(spec) return dispatcher("window.float", spec or {}) end,
      fullscreen = function(spec) return dispatcher("window.fullscreen", spec or {}) end,
      fullscreen_state = function(spec) return dispatcher("window.fullscreen_state", spec or {}) end,
      pseudo = function(spec) return dispatcher("window.pseudo", spec or {}) end,
      move = function(spec) return dispatcher("window.move", spec or {}) end,
      swap = function(spec) return dispatcher("window.swap", spec or {}) end,
      center = function(spec) return dispatcher("window.center", spec or {}) end,
      cycle_next = function(spec) return dispatcher("window.cycle_next", spec or {}) end,
      bring_to_top = function() return dispatcher("window.bring_to_top", {}) end,
      tag = function(spec) return dispatcher("window.tag", spec or {}) end,
      clear_tags = function(spec) return dispatcher("window.clear_tags", spec or {}) end,
      toggle_swallow = function() return dispatcher("window.toggle_swallow", {}) end,
      pin = function(spec) return dispatcher("window.pin", spec or {}) end,
      alter_zorder = function(spec) return dispatcher("window.alter_zorder", spec or {}) end,
      set_prop = function(spec) return dispatcher("window.set_prop", spec or {}) end,
      deny_from_group = function(spec) return dispatcher("window.deny_from_group", spec or {}) end,
      drag = function() return dispatcher("window.drag", {}) end,
      resize = function(spec) return dispatcher("window.resize", spec or {}) end,
    },
    workspace = {
      rename = function(spec) return dispatcher("workspace.rename", spec or {}) end,
      move = function(spec) return dispatcher("workspace.move", spec or {}) end,
      swap_monitors = function(spec) return dispatcher("workspace.swap_monitors", spec or {}) end,
      toggle_special = function(name) return dispatcher("workspace.toggle_special", { name = name }) end,
    },
    group = {
      toggle = function(spec) return dispatcher("group.toggle", spec or {}) end,
      next = function(spec) return dispatcher("group.next", spec or {}) end,
      prev = function(spec) return dispatcher("group.prev", spec or {}) end,
      active = function(spec) return dispatcher("group.active", spec or {}) end,
      move_window = function(spec) return dispatcher("group.move_window", spec or {}) end,
      lock = function(spec) return dispatcher("group.lock", spec or {}) end,
      lock_active = function(spec) return dispatcher("group.lock_active", spec or {}) end,
    },
    cursor = {
      move_to_corner = function(spec) return dispatcher("cursor.move_to_corner", spec or {}) end,
      move = function(spec) return dispatcher("cursor.move", spec or {}) end,
    },
  },
}

local ok, err = pcall(dofile, config_path)
if not ok then
  io.stderr:write("hypr-binds: failed to load config: ", tostring(err), "\n")
  os.exit(1)
end

local function render_dispatcher(d, opts)
  if type(d) == "function" then
    if type(opts) == "table" and opts.description then
      return tostring(opts.description)
    end
    return "lua function"
  end

  if type(d) ~= "table" then
    return tostring(d)
  end

  local kind = d.__kind or "table"
  if kind == "exec_cmd" then
    return "exec " .. tostring(d.cmd or d.value or "")
  end
  if kind == "layout" then
    return "layout " .. tostring(d.msg or d.value or "")
  end
  if kind == "focus" then
    if d.workspace then return "focus workspace " .. tostring(d.workspace) end
    if d.monitor then return "focus monitor " .. tostring(d.monitor) end
    if d.direction then return "focus " .. tostring(d.direction) end
    return "focus"
  end
  if kind == "window.drag" then return "window drag" end
  if kind == "window.resize" then return "window resize" end
  if kind == "window.move" then
    if d.workspace then return "move workspace " .. tostring(d.workspace) end
    if d.direction then return "move " .. tostring(d.direction) end
    if d.x or d.y then return "move " .. tostring(d.x or 0) .. "," .. tostring(d.y or 0) end
    if d.out_of_group then return "move out_of_group" end
    return "move"
  end
  if kind == "window.swap" then
    if d.direction then return "swap " .. tostring(d.direction) end
    return "swap"
  end
  if kind == "window.cycle_next" then
    if d.previous then return "cycle previous" end
    return "cycle next"
  end
  if kind == "window.bring_to_top" then return "bring to top" end
  if kind == "window.center" then return "center" end
  if kind == "window.float" then return "float" end
  if kind == "window.fullscreen" then
    local mode = d.mode and (" " .. tostring(d.mode)) or ""
    local action = d.action and (" " .. tostring(d.action)) or ""
    return "fullscreen" .. mode .. action
  end
  if kind == "window.pseudo" then return "pseudo" end
  if kind == "group.toggle" then return "group toggle" end
  if kind == "group.next" then return "group next" end
  if kind == "group.prev" then return "group prev" end
  if kind == "workspace.toggle_special" then return "special " .. tostring(d.name or "") end
  if kind == "pass" then return "pass" end
  if kind == "send_shortcut" then return "send_shortcut" end
  if kind == "send_key_state" then return "send_key_state" end
  if kind == "dpms" then return "dpms" end
  if kind == "global" then return "global" end
  if kind == "submap" then return "submap " .. tostring(d.name or "") end
  if kind == "exit" then return "exit" end
  if kind == "window.kill" then return "kill" end
  if kind == "window.close" then return "close" end
  return kind
end

local function render_opts(opts)
  if type(opts) ~= "table" then
    return ""
  end

  local flags = {}
  for _, key in ipairs({ "mouse", "locked", "release", "click", "drag", "long_press", "repeating", "non_consuming", "auto_consuming" }) do
    if opts[key] then
      flags[#flags + 1] = key
    end
  end

  if #flags == 0 then
    return ""
  end

  return " [" .. table.concat(flags, ",") .. "]"
end

local function render_type(opts)
  if type(opts) ~= "table" then
    return "key"
  end
  if opts.mouse then
    return "mouse"
  end
  if opts.locked and opts.repeating then
    return "lock-r"
  end
  if opts.locked then
    return "lock"
  end
  return "key"
end

table.sort(binds, function(a, b)
  if a.keys == b.keys then
    return render_dispatcher(a.dispatcher, a.opts) < render_dispatcher(b.dispatcher, b.opts)
  end
  return a.keys < b.keys
end)

for _, item in ipairs(binds) do
  local key = item.keys
  if #key > 38 then
    key = key:sub(1, 35) .. "..."
  end
  print(string.format("%-7s | %-38s | %s%s", render_type(item.opts), key, render_dispatcher(item.dispatcher, item.opts), render_opts(item.opts)))
end
LUA
}

if [[ -z "$lua_bin" ]]; then
  echo "hypr-binds: missing lua interpreter (need lua or luajit)" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  echo "hypr-binds: missing config: $config_file" >&2
  exit 1
fi

table_output="$(render_table_from_lua)"

if [[ -z "$table_output" ]]; then
  echo "hypr-binds: no bind lines found in $config_file" >&2
  exit 1
fi

if [[ "$mode" = "print" ]]; then
  printf '%s\n' "$table_output"
  exit 0
fi

pick=""
if command -v rofi >/dev/null 2>&1; then
  set +e
  pick="$(
    printf '%s\n' "$table_output" | rofi -dmenu -i \
      -p 'Hypr Keys' \
      -mesg 'Enter copies row | Esc closes' \
      -theme "$HOME/.config/rofi/actions.rasi"
  )"
  status=$?
  set -e
  [ "$status" -eq 0 ] || exit 0
elif command -v fzf >/dev/null 2>&1; then
  set +e
  pick="$(
    printf '%s\n' "$table_output" | fzf \
      --height=70% \
      --layout=reverse \
      --border \
      --prompt='hypr-binds> ' \
      --header='Enter copies row | Esc closes'
  )"
  status=$?
  set -e
  [ "$status" -eq 0 ] || exit 0
else
  printf '%s\n' "$table_output"
  exit 0
fi

[ -n "$pick" ] || exit 0

if command -v wl-copy >/dev/null 2>&1; then
  printf '%s\n' "$pick" | wl-copy
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a Hyprland "Keybind copied" "$pick"
  fi
fi
