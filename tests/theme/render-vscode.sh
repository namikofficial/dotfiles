#!/usr/bin/env bash
# Render the generated VS Code theme in a real VS Code window and capture
# screenshots. Manual visual check: it needs a running Hyprland (Wayland)
# session, VS Code, grim and jq, and it briefly takes over the focused
# workspace. It uses a throwaway profile; your settings and extensions are
# never read or written.
#
#   tests/theme/render-vscode.sh PALETTE.json OUT_DIR [view ...]
#
# Views: editor scm diff palette terminal problems settings (default: all).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
palette="${1:?usage: render-vscode.sh PALETTE.json OUT_DIR [view ...]}"
out="${2:?usage: render-vscode.sh PALETTE.json OUT_DIR [view ...]}"
shift 2
views=("$@")
[[ ${#views[@]} -gt 0 ]] || views=(editor scm diff palette terminal problems settings)
class="com.microsoft.VSCode"
# The throwaway workspace has a unique name so every hyprctl/grim call targets
# only the window this script launched, never one of your own VS Code windows.
marker="nxtheme-render-$$"

for tool in grim hyprctl jq git /usr/bin/code; do
  command -v "$tool" >/dev/null 2>&1 || { echo "render-vscode: missing $tool" >&2; exit 2; }
done

work="$(mktemp -d)"
mkdir -p "$out" "$work/ud/User" "$work/ext" "$work/ws"
cleanup() {
  pkill -f -- "--user-data-dir $work/ud" 2>/dev/null || pkill -f "$work/ud" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

python3 -I "$root/hypr/scripts/vscode-theme.py" "$palette" \
  --extension-dir "$work/ext/noxflow.dynamic-theme-0.0.1"

cp -r "$root/tests/theme/fixtures/vscode/workspace" "$work/ws/$marker"
cat >"$work/ud/User/settings.json" <<'JSON'
{
  "workbench.colorTheme": "NoxFlow Dynamic",
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "none",
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "chat.disableAIFeatures": true,
  "workbench.tips.enabled": false,
  "editor.fontFamily": "JetBrainsMono Nerd Font, monospace",
  "editor.fontSize": 14,
  "window.restoreWindows": "none",
  "git.openRepositoryInParentFolders": "never"
}
JSON
(
  cd "$work/ws/$marker"
  git init -q -b main
  git -c user.name=t -c user.email=t@t add -A
  git -c user.name=t -c user.email=t@t commit -qm init
  git show HEAD:src/server.ts >"$work/server.HEAD.ts"
  sed -i 's/DEFAULT_PORT = 8080/DEFAULT_PORT = 9090/' src/server.ts
  sed -i 's/hits: 0 }/hits: 1 }/' src/lib.rs
  git add src/lib.rs
  rm ci.yaml
  echo "print('new')" >src/new_file.py
)

code_cmd=(/usr/bin/code --user-data-dir "$work/ud" --extensions-dir "$work/ext")
setsid "${code_cmd[@]}" --new-window "$work/ws/$marker" "$work/ws/$marker/src/server.ts" >/dev/null 2>&1 &

geometry() {
  hyprctl clients -j | jq -r --arg c "$class" --arg m "$marker" \
    '.[] | select(.class == $c and (.title | contains($m))) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -1
}
for _ in $(seq 1 40); do
  [[ -n "$(geometry)" ]] && break
  sleep 1
done
[[ -n "$(geometry)" ]] || { echo "render-vscode: VS Code window never appeared" >&2; exit 1; }
hyprctl dispatch "hl.dsp.focus({ window = \"title:.*$marker.*\" })" >/dev/null
sleep 6 # extension host, TypeScript server and git need a moment

key() { # key MODS KEY
  hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$1\", key = \"$2\", window = \"title:.*$marker.*\" })" >/dev/null
}
shot() {
  sleep 2
  grim -g "$(geometry)" "$out/$1.png"
  echo "captured $out/$1.png"
}

for view in "${views[@]}"; do
  case "$view" in
    editor) key "CTRL_SHIFT" "E"; shot editor ;;
    scm) key "CTRL_SHIFT" "G"; shot scm ;;
    diff)
      "${code_cmd[@]}" --reuse-window --diff "$work/server.HEAD.ts" "$work/ws/$marker/src/server.ts" >/dev/null 2>&1
      shot diff ;;
    palette) key "CTRL_SHIFT" "P"; shot palette; key "" "Escape" ;;
    terminal) key "CTRL" "grave"; sleep 3; shot terminal ;;
    problems) key "CTRL_SHIFT" "M"; shot problems ;;
    settings) key "CTRL" "comma"; shot settings; key "CTRL" "W" ;;
    *) echo "render-vscode: unknown view $view" >&2 ;;
  esac
done
