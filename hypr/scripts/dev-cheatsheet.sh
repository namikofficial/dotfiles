#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
mkdir -p "$state_dir"

pid_file="$state_dir/rofi-dev-cheatsheet.pid"
cache_file="$state_dir/dev-cheatsheet.tsv"

config_dir="${DEV_CHEATSHEET_DIR:-$HOME/.config/dev-cheatsheet}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
default_dir="$(cd -- "$script_dir/.." && pwd)/dev-cheatsheet-defaults"
theme_file="$HOME/.config/rofi/cheatsheet.rasi"

modes=(
  "all:All"
  "daily:Daily"
  "keyboard:Keyboard"
  "hyprland:Hyprland"
  "zsh_aliases:Zsh Aliases"
  "git:Git"
  "docker:Docker"
  "neovim:Neovim"
  "tmux_zellij:Tmux/Zellij"
  "system:System"
  "plugins:Plugins"
  "configs:Configs"
  "custom:Custom"
)

stop_if_running() {
  local file="$1"
  [ -f "$file" ] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$file"
    return 0
  fi
  rm -f "$file"
  return 1
}

notify() {
  local title="$1"
  local body="$2"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Dev Cheatsheet" "$title" "$body"
}

bootstrap_defaults() {
  mkdir -p "$config_dir"
  [ -d "$default_dir" ] || return 0

  local file base
  for file in "$default_dir"/*.yaml; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    [ -f "$config_dir/$base" ] || cp "$file" "$config_dir/$base"
  done
}

need_cache_rebuild() {
  [ -f "$cache_file" ] || return 0
  [ "$0" -nt "$cache_file" ] && return 0

  local file
  for file in "$config_dir"/*.yaml; do
    [ -f "$file" ] || continue
    [ "$file" -nt "$cache_file" ] && return 0
  done

  return 1
}

build_cache() {
  python3 - "$config_dir" "$cache_file" <<'PY'
import csv
import glob
import os
import re
import sys

try:
    import yaml
except Exception as exc:
    print(f"dev-cheatsheet: python yaml module missing: {exc}", file=sys.stderr)
    sys.exit(1)

config_dir, cache_file = sys.argv[1], sys.argv[2]
rows = []

slugify_re = re.compile(r"[^a-z0-9_]+")

def slugify(value: str) -> str:
    value = value.strip().lower().replace("-", "_").replace(" ", "_")
    value = slugify_re.sub("", value)
    return value or "custom"

for path in sorted(glob.glob(os.path.join(config_dir, "*.yaml"))):
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}

    if not isinstance(data, dict):
        continue

    file_slug = slugify(os.path.splitext(os.path.basename(path))[0])
    category = str(data.get("category") or file_slug.replace("_", " ").title()).strip()
    slug = slugify(str(data.get("slug") or file_slug))
    entries = data.get("entries") or []

    if not isinstance(entries, list):
        continue

    for item in entries:
        if not isinstance(item, dict):
            continue

        key = str(item.get("key", "")).strip()
        description = str(item.get("description", "")).strip()
        if not key or not description:
            continue

        copy_text = str(item.get("copy") or key).strip()
        source = str(item.get("source") or "").strip()

        tags = item.get("tags") or []
        if isinstance(tags, str):
            tags = [tags]
        if not isinstance(tags, list):
            tags = []

        norm_tags = [slugify(str(tag)) for tag in tags if str(tag).strip()]
        rows.append((slug, category, key, description, copy_text, source, ";".join(norm_tags)))

rows.sort(key=lambda r: (r[0], r[2].lower(), r[3].lower()))

os.makedirs(os.path.dirname(cache_file), exist_ok=True)
with open(cache_file, "w", encoding="utf-8", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
    writer.writerows(rows)
PY
}

print_mode_rows() {
  local mode="$1"

  python3 - "$cache_file" "$mode" <<'PY'
import csv
import sys

cache_file, mode = sys.argv[1], sys.argv[2]

rows = []
try:
    with open(cache_file, "r", encoding="utf-8") as fh:
        reader = csv.reader(fh, delimiter="\t")
        for row in reader:
            if len(row) != 7:
                continue
            rows.append(row)
except FileNotFoundError:
    pass

mode = mode.strip().lower() or "all"

def is_daily(row):
    tags = set(filter(None, row[6].split(";")))
    return "daily" in tags

for row in rows:
    slug, category, key, desc, copy_text, source, tags = row

    if mode == "all":
        pass
    elif mode == "daily":
        if not is_daily(row):
            continue
    elif slug != mode:
        continue

    display = f"{key:<24} {desc:<72} [{category}]"
    info = "\t".join([copy_text, source, f"{key} -> {desc}"])
    print(f"{display}\0info\x1f{info}")
PY
}

handle_selection() {
  local info copy_text summary

  info="${ROFI_INFO:-}"
  if [ -n "$info" ]; then
    copy_text="${info%%$'\t'*}"
    summary="${info##*$'\t'}"
  else
    copy_text="${1:-}"
    summary="${1:-Entry}"
  fi

  [ -n "$copy_text" ] || exit 0

  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$copy_text" | wl-copy
    notify "Copied" "$summary"
  else
    notify "Clipboard unavailable" "Install wl-clipboard for copy support"
  fi
}

handle_script_mode() {
  local mode="${1:-all}"

  bootstrap_defaults
  need_cache_rebuild && build_cache

  if [ "${ROFI_RETV:-0}" -eq 1 ] && [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
    handle_selection "$2"
    exit 0
  fi

  if [ "${ROFI_RETV:-0}" -eq 10 ] && [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
    handle_selection "$2"
    exit 0
  fi

  printf '\0prompt\x1fDev Cheatsheet\n'
  printf '\0message\x1fType to search | Ctrl+Tab switch tabs | Enter/Ctrl+Y copy | Esc close\n'
  print_mode_rows "$mode"
}

# Rofi script mode entrypoint.
if [ "${1:-}" = "--mode" ]; then
  mode="${2:-all}"
  selected="${3:-}"
  handle_script_mode "$mode" "$selected"
  exit 0
fi

bootstrap_defaults
need_cache_rebuild && build_cache

# Same key toggles this overlay off.
if stop_if_running "$pid_file"; then
  exit 0
fi

modi_arg=""
for pair in "${modes[@]}"; do
  slug="${pair%%:*}"
  name="${pair#*:}"
  [ -n "$modi_arg" ] && modi_arg+=","
  modi_arg+="$name:$0 --mode $slug"
done

set +e
rofi \
  -show "All" \
  -modi "$modi_arg" \
  -no-sort \
  -normal-window \
  -show-icons \
  -kb-mode-next 'Control+Tab' \
  -kb-mode-previous 'Control+ISO_Left_Tab' \
  -kb-accept-entry 'Return' \
  -kb-custom-1 'Control+y' \
  -kb-cancel 'Escape,Control+g,Super+period' \
  -theme "$theme_file" \
  -pid "$pid_file"
status=$?
set -e

rm -f "$pid_file"
[ "$status" -eq 0 ] || exit 0
