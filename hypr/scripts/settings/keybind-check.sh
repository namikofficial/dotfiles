#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)"
LUA_CONF="$ROOT_DIR/hypr/hyprland.lua"
DOCS_CHECK="$ROOT_DIR/setup/check-keybinds.sh"

lua_bin=""
for candidate in lua luajit; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_bin="$(command -v "$candidate")"
    break
  fi
done

extract_lua_keys() {
  "$lua_bin" - "$LUA_CONF" <<'LUA'
local config_path = arg[1]
local keys = {}

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
  bind = function(keys_value)
    keys[#keys + 1] = keys_value
  end,
  dispatch = function() end,
  exec_cmd = function(cmd)
    return dispatcher("exec_cmd", { cmd = cmd })
  end,
  dsp = {
    exec_cmd = function(cmd) return dispatcher("exec_cmd", { cmd = cmd }) end,
    layout = function(msg) return dispatcher("layout", { msg = msg }) end,
    focus = function(spec) return dispatcher("focus", spec or {}) end,
    exit = function() return dispatcher("exit", {}) end,
    submap = function(name) return dispatcher("submap", { name = name }) end,
    pass = function(spec) return dispatcher("pass", spec or {}) end,
    send_shortcut = function(spec) return dispatcher("send_shortcut", spec or {}) end,
    send_key_state = function(spec) return dispatcher("send_key_state", spec or {}) end,
    dpms = function(spec) return dispatcher("dpms", spec or {}) end,
    event = function(msg) return dispatcher("event", { msg = msg }) end,
    global = function(msg) return dispatcher("global", { msg = msg }) end,
    force_idle = function(seconds) return dispatcher("force_idle", { seconds = seconds }) end,
    no_op = function() return dispatcher("no_op", {}) end,
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
  io.stderr:write("hypr keycheck: failed to load config: ", tostring(err), "\n")
  os.exit(1)
end

table.sort(keys)
for _, key in ipairs(keys) do
  print(key)
end
LUA
}

if [[ -z "$lua_bin" ]]; then
  echo "Missing lua interpreter (need lua or luajit)" >&2
  exit 1
fi

if [[ ! -f "$LUA_CONF" ]]; then
  echo "Missing hyprland.lua at $LUA_CONF" >&2
  exit 1
fi

keys="$(extract_lua_keys)"

if [[ -z "$keys" ]]; then
  echo "hypr keycheck: no bind lines found" >&2
  exit 1
fi

dupes="$(printf '%s\n' "$keys" | sort | uniq -d || true)"
fail=0
if [[ -n "$dupes" ]]; then
  printf '%s\n' "$dupes" | sed 's/^/DUPLICATE: /'
  fail=1
fi

if [[ -x "$DOCS_CHECK" ]]; then
  "$DOCS_CHECK" || fail=1
else
  echo "hypr keycheck: docs parity check missing: $DOCS_CHECK" >&2
  exit 1
fi

exit "$fail"
