#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS="$REPO_DIR/docs/KEYBINDS.md"
CONF="$REPO_DIR/hypr/hyprland.lua"
HYPR_BINDS="$REPO_DIR/hypr/scripts/hypr-binds.sh"

python3 - "$DOCS" "$CONF" "$HYPR_BINDS" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

docs_path = Path(sys.argv[1])
conf_path = Path(sys.argv[2])
hypr_binds = Path(sys.argv[3])

def normalize_key(text: str) -> str:
    text = text.strip()
    text = text.replace("SUPER", "Super").replace("SHIFT", "Shift").replace("ALT", "Alt").replace("CTRL", "Ctrl")
    text = text.replace("backslash", "\\")
    text = text.replace("Backslash", "\\")
    text = text.replace("grave", "`")
    text = text.replace("comma", ",")
    text = text.replace("period", ".")
    text = text.replace("slash", "/")
    text = text.replace("Slash", "/")
    text = text.replace("tab", "Tab")
    text = text.replace("Tab", "Tab")
    text = text.replace("Return", "Return")
    text = text.replace("space", "Space")
    text = re.sub(r"\s+\+\s+", " + ", text)
    return text

def parse_docs() -> dict[str, str]:
    wanted = {
        "Launch / Session",
        "AI Helper",
    }
    section = None
    result: dict[str, str] = {}
    for line in docs_path.read_text().splitlines():
      if line.startswith("## "):
        section = line[3:].strip()
        continue
      if section not in wanted:
        continue
      if not line.startswith("| `"):
        continue
      cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
      if len(cells) < 3:
        continue
      key_cell = cells[0]
      action = cells[1]
      target = cells[2].strip("`")
      key_variants = re.findall(r"`([^`]+)`", key_cell)
      if not key_variants:
        key_variants = [key_cell.strip("`")]
      for key in key_variants:
        normalized = normalize_key(key)
        if not normalized or normalized.endswith("+") or normalized.startswith("Fn +"):
          continue
        result[normalized] = f"{action} :: {target}"
    return result

def parse_actual() -> dict[str, str]:
    output = subprocess.check_output([str(hypr_binds), "--print", "--conf", str(conf_path)], text=True)
    result: dict[str, str] = {}
    for line in output.splitlines():
      if " | " not in line:
        continue
      parts = line.split(" | ", 2)
      if len(parts) != 3:
        continue
      _, key, action = parts
      result[normalize_key(key)] = action
    return result

docs = parse_docs()
actual = parse_actual()

errors = []
for key, expected in docs.items():
    if key not in actual:
        errors.append(f"missing keybind: {key}")
        continue
    actual_action = actual[key]
    target = expected.split(" :: ", 1)[1]
    if target and target not in actual_action:
        errors.append(f"mismatch: {key} -> docs target '{target}' not found in actual '{actual_action}'")

if errors:
    for item in errors:
        print(f"FAIL {item}")
    sys.exit(1)

print("OK   keybind docs match the canonical launch/session entries")
PY
