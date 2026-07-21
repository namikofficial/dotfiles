#!/usr/bin/env python3
"""Generate the Hyprland keybind portion of docs/KEYBINDS.md.

The binding files are Lua, so this script runs them in a capture-only Lua
environment. No commands are executed and no compositor connection is made.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs" / "KEYBINDS.md"
SOURCES = (
    ROOT / "hypr" / "conf" / "40-binds-launch.lua",
    ROOT / "hypr" / "conf" / "50-binds-layout.lua",
    ROOT / "hypr" / "conf" / "60-binds-media.lua",
)
BEGIN = "<!-- BEGIN GENERATED HYPRLAND KEYBINDS -->"
END = "<!-- END GENERATED HYPRLAND KEYBINDS -->"

HARNESS = r'''
local sources = {...}
local records = {}
local current_source = ""

local function json_escape(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  value = value:gsub("\r", "\\r")
  return '"' .. value .. '"'
end

local function encode(value)
  local out = {}
  for _, item in ipairs(value) do
    out[#out + 1] = json_escape(item)
  end
  return "[" .. table.concat(out, ",") .. "]"
end

local function option_suffix(opts)
  if type(opts) ~= "table" then return "" end
  local flags = {}
  if opts.mouse then flags[#flags + 1] = "mouse" end
  if opts.locked then flags[#flags + 1] = "locked" end
  if opts.repeating then flags[#flags + 1] = "repeating" end
  return table.concat(flags, ",")
end

local function record(kind, keys, target, opts)
  records[#records + 1] = {kind, keys, target, option_suffix(opts), current_source}
end

local function dispatcher(namespace, name)
  return function(value)
    local suffix = ""
    if value ~= nil then
      if type(value) == "table" then
        local fields = {}
        for key, item in pairs(value) do
          fields[#fields + 1] = tostring(key) .. "=" .. tostring(item)
        end
        table.sort(fields)
        suffix = " " .. table.concat(fields, ",")
      else
        suffix = " " .. tostring(value)
      end
    end
    return namespace .. "." .. name .. suffix
  end
end

local function namespace_proxy(namespace)
  return setmetatable({}, {
    __index = function(_, name)
      return dispatcher(namespace, name)
    end,
  })
end

hl = {
  dsp = {
    window = namespace_proxy("window"),
    group = namespace_proxy("group"),
    workspace = namespace_proxy("workspace"),
    layout = dispatcher("layout", "dispatch"),
    focus = dispatcher("focus", "dispatch"),
    exec_cmd = function(command) return "exec " .. tostring(command) end,
  },
}

NOX_HYPR = {
  home = os.getenv("NOX_REPO_HOME") or "/home/user",
  terminal = "kitty",
  fileManager = "kitty --class yazi -e yazi",
  browser = "google-chrome-stable",
  editor = "code",
  ide = "android-studio",
  menu = "~/.config/hypr/scripts/desktop-palette.sh",
  overview = "~/.config/hypr/scripts/workspace-overview.sh",
  mainMod = "SUPER",
}

function NOX_HYPR.bind(keys, target, opts) record("bind", keys, target, opts) end
function NOX_HYPR.exec(keys, command, opts) record("exec", keys, command, opts) end
function NOX_HYPR.workspace(keys, target, opts) record("workspace", keys, target, opts) end
function NOX_HYPR.move_workspace(keys, target, opts) record("move_workspace", keys, target, opts) end

for _, source in ipairs(sources) do
  current_source = source
  local chunk, err = loadfile(source)
  if not chunk then error(err) end
  chunk()
end

for _, item in ipairs(records) do
  print(encode(item))
end
'''


def run_capture() -> list[list[str]]:
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as handle:
        handle.write(HARNESS)
        harness = Path(handle.name)
    try:
        env = os.environ.copy()
        env["NOX_REPO_HOME"] = str(Path.home())
        command = ["lua", str(harness), *(str(source) for source in SOURCES)]
        completed = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr.strip() or "Lua capture harness failed")
        return [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
    finally:
        harness.unlink(missing_ok=True)


def clean(value: str) -> str:
    value = value.replace(str(Path.home()), "~")
    value = value.replace("/home/user", "~")
    value = value.replace("~/.config/hypr/scripts/", "~/.config/hypr/scripts/")
    return value


def key_label(value: str) -> str:
    replacements = {
        "SUPER": "Super",
        "SHIFT": "Shift",
        "CTRL": "Ctrl",
        "ALT": "Alt",
        "Return": "Return",
        "Slash": "/",
        "comma": ",",
        "backslash": "\\",
        "grave": "`",
        "bracketleft": "[",
        "bracketright": "]",
        "period": ".",
        "semicolon": ";",
        "mouse_down": "mouse wheel down",
        "mouse_up": "mouse wheel up",
    }
    parts = [replacements.get(part, part) for part in value.split(" + ")]
    return " + ".join(parts)


def dispatcher_action(target: str) -> tuple[str, str]:
    if target.startswith("window.close"):
        return "Close active window", ""
    if target.startswith("window.fullscreen"):
        return "Toggle fullscreen/maximized", target.removeprefix("window.fullscreen ")
    if target.startswith("window.move"):
        return "Move active window", target.removeprefix("window.move ")
    if target.startswith("window.resize"):
        return "Resize active window", target.removeprefix("window.resize ")
    if target.startswith("window.drag"):
        return "Drag active window", ""
    if target.startswith("window.center"):
        return "Center active window", ""
    if target.startswith("window.pseudo"):
        return "Toggle pseudo-tile", ""
    if target.startswith("group."):
        return "Window group action", target.removeprefix("group.")
    if target.startswith("layout.dispatch"):
        return "Layout action", target.removeprefix("layout.dispatch ")
    if target.startswith("focus.dispatch"):
        return "Focus window", target.removeprefix("focus.dispatch ")
    if target.startswith("exec "):
        return "Execute command", clean(target.removeprefix("exec "))
    return "Hyprland action", target


def record_to_row(record: list[str]) -> tuple[str, str, str, str]:
    kind, keys, target, flags, _ = record
    keys = key_label(keys)
    if kind == "workspace":
        return keys, "Focus workspace", clean(target)
    if kind == "move_workspace":
        return keys, "Move window to workspace", clean(target)
    if kind == "exec":
        action = "Execute command"
        if flags:
            action += f" ({flags})"
        return keys, action, clean(target)
    action, destination = dispatcher_action(clean(target))
    if flags:
        action += f" ({flags})"
    return keys, action, destination


def section_for(source: str) -> str:
    if "40-binds-launch" in source:
        return "Launch / Session"
    if "50-binds-layout" in source:
        return "Window / Layout"
    return "Media / Screen / Clipboard"


def render(records: list[list[str]]) -> str:
    groups: dict[str, list[tuple[str, str, str]]] = {
        "Launch / Session": [],
        "Window / Layout": [],
        "Focus / Move / Resize": [],
        "Workspace": [],
        "Media / Screen / Clipboard": [],
    }
    for record in records:
        kind, keys, target, _, source = record
        if "60-binds-media" in source:
            group = "Media / Screen / Clipboard"
        elif "40-binds-launch" in source:
            group = "Launch / Session"
        elif kind in {"workspace", "move_workspace"}:
            group = "Workspace"
        elif "focus.dispatch" in target or "window.move" in target or "window.resize" in target:
            group = "Focus / Move / Resize"
        else:
            group = "Window / Layout"
        groups[group].append(record_to_row(record))

    lines = [BEGIN, "", "<!-- Generated by setup/generate-keybind-docs.py; do not edit this section manually. -->", ""]
    for title, rows in groups.items():
        if not rows:
            continue
        lines += [f"## {title}", "", "| Keybind | Action | Script/Target |", "|---|---|---|"]
        seen = set()
        for key, action, target in rows:
            row = (key, action, target)
            if row in seen:
                continue
            seen.add(row)
            target = target or "—"
            lines.append(f"| `{key}` | {action} | `{target}` |")
        lines.append("")
    lines += [END, ""]
    return "\n".join(lines)


def update_document(document: str, generated: str) -> str:
    if BEGIN in document and END in document:
        before, remainder = document.split(BEGIN, 1)
        _, after = remainder.split(END, 1)
        if after.lstrip().startswith("## Launch / Session"):
            after = after[after.index("## Shell UX"):]
        return before.rstrip() + "\n\n" + generated.rstrip() + after
    start = document.index("## Launch / Session")
    end = document.index("## Shell UX")
    return document[:start].rstrip() + "\n\n" + generated.rstrip() + "\n\n" + document[end:]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if docs/KEYBINDS.md is stale")
    args = parser.parse_args()
    generated = update_document(DOC.read_text(encoding="utf-8"), render(run_capture()))
    current = DOC.read_text(encoding="utf-8")
    if args.check:
        if generated != current:
            print(f"stale generated keybind documentation: {DOC}", file=sys.stderr)
            return 1
        print("keybind documentation is current")
        return 0
    DOC.write_text(generated, encoding="utf-8")
    print(f"generated {DOC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
