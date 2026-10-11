#!/usr/bin/env bash
set -euo pipefail

# Static regression checks for the Super+Space launcher contract.  These tests
# deliberately inspect the source instead of opening a graphical session, so
# they can run in CI and on recovery consoles.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QML="$ROOT/shell/noxflow/surfaces/launcher/Launcher.qml"
RADIAL="$ROOT/shell/noxflow/surfaces/radialmenu/RadialWheel.qml"
ISLAND="$ROOT/shell/noxflow/island"
TOP_CHROME="$ROOT/shell/noxflow/TopChrome.qml"
TEXT_FIELD="$ROOT/shell/noxflow/components/TextField.qml"
SHELL="$ROOT/shell/noxflow/shell.qml"
ROFI="$ROOT/hypr/scripts/launcher.sh"
KEYBINDS="$ROOT/docs/KEYBINDS.md"

has() {
  local needle="$1" file="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

# Keyboard activation must be handled by the focused search field and support
# predictable selection movement.  Keep these checks source-level because the
# QML runtime is not available in all test environments.
has 'onAccepted: root.activateSelected()' "$QML"
has 'onNavigateUp: root.moveList(-1)' "$QML"
has 'onNavigateDown: root.moveList(1)' "$QML"
has 'searchField.focusInput()' "$QML"
has 'focus: lifecycle.active' "$QML"
has 'focus: true' "$TEXT_FIELD"
has 'WlrKeyboardFocus.Exclusive' "$TOP_CHROME"
has 'root.activateSelected()' "$QML"
has '["gtk-launch", item.actionParams.desktopId]' "$QML"
has 'root.launchError =' "$QML"
has 'root.scanError =' "$QML"
has 'IconImage' "$QML"
has 'Quickshell.iconPath' "$QML"
# NF-02: window focus from the launcher must be shell-local (hyprctl), not a
# runAction({window_focus: ...}) call.
has 'focusWindowByAddress' "$QML"
has 'hyprctl", "dispatch", "focuswindow"' "$QML"
if grep -Fq 'runAction({window_focus' "$QML"; then
  printf 'launcher must not route window focus through noxd.runAction\n' >&2
  exit 1
fi

# Super+Space must be hosted by the existing Dynamic Island. A launcher entry
# in MorphSurface would create a second layer window and regress the morph.
# Phase 3 split the island: the launcher overlay lives in island/IslandLayers.qml
# (the Loader) while the host in island/IslandHost.qml exposes the toggle.
has 'launcherVisible' "$ISLAND/IslandLayers.qml"
has 'sourceComponent: root.launcherComponent' "$ISLAND/IslandLayers.qml"
has 'function toggleLauncher()' "$ISLAND/IslandLayers.qml"
has 'function toggleLauncher()' "$ISLAND/IslandHost.qml"
has 'height: parent.height' "$ISLAND/IslandCard.qml"
if grep -Fq '"launcher": launcherComponent' "$SHELL"; then
  printf 'launcher must not be registered in MorphSurface\n' >&2
  exit 1
fi

# Desktop discovery/launch must use desktop IDs and preserve the standard
# application directories, including the user-local override location.
has '/usr/local/share/applications' "$ROFI"
has 'desktop_id' "$ROFI"
has 'gtk-launch' "$ROFI"
has '--list-json' "$ROFI"
has 'NoDisplay' "$ROFI"
has 'Hidden' "$ROFI"
has '\( -type f -o -type l \)' "$ROFI"

# Clipboard mode delegates to the installed Author Clipboard picker instead
# of displaying the shell's historical empty JSON stub.
has 'action:"open_clipboard"' "$QML"
has '/.config/hypr/scripts/cliphist-rofi.sh' "$QML"

# The documented Super+Space path is the NoxFlow surface, with Rofi retained
# as an explicit recovery option.
has 'Super + Space' "$KEYBINDS"
has 'Rofi' "$KEYBINDS"
has 'NoxFlow' "$KEYBINDS"

# NF-07: AI stale callback protection. The guard moved to the shared
# services/AiClient.qml (decision 4), so assert it there rather than in the
# launcher, which is now a thin adapter over that client.
AI_CLIENT="$ROOT/shell/noxflow/services/AiClient.qml"
has 'generation' "$AI_CLIENT"
has 'gen !== generation' "$AI_CLIENT"
has 'function reset()' "$AI_CLIENT"
has 'aiClient.reset()' "$QML"
# The launcher must not carry its own AI transport any more.
if grep -Fq 'new XMLHttpRequest()' "$QML"; then
  printf 'launcher must use the shared AiClient, not its own XMLHttpRequest\n' >&2
  exit 1
fi
if grep -Fq 'NOXFLOW_AI_ENDPOINT' "$QML"; then
  printf 'launcher must not read AI configuration from env vars\n' >&2
  exit 1
fi

# Phase 1 — no view may launch a binary that is not installed on this
# workstation, and no view may hardcode an external command at all.
APPS="$ROOT/shell/noxflow/config/Apps.qml"
has 'command -v' "$APPS"
has 'function unavailableReason' "$APPS"
# A view may name an uninstalled program in a comment or in the nerd-font icon
# map, but never as an executed command. These patterns match the invocation
# contexts only: a Process command array, an action payload's command field, or
# a raw shell pipeline stage.
INVOKE_RE='command: *\[[^]]*"$stale"|command: *\[? *"$stale"|command: *"$stale"|command:"$stale"|\| *"$stale" |&& *"$stale"'
for stale in gnome-control-center zenity magick thunar; do
  hits="$(grep -RnE "$INVOKE_RE" \
      "$ROOT/shell/noxflow/surfaces" "$ROOT/shell/noxflow/bar" \
      "$ROOT/shell/noxflow/island" "$ROOT/shell/noxflow/shell.qml" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf 'view still invokes the uninstalled program: %s\n%s\n' "$stale" "$hits" >&2
    exit 1
  fi
done
# Quickshell.exec does not exist in 0.3.1; only execDetached does. Scope the
# search to shipped shell code — the test files assert on the very string they
# are forbidding.
if grep -Rq 'Quickshell\.exec(' "$ROOT/shell/noxflow" \
    --include='*.qml' --include='*.js' --exclude-dir=tests; then
  printf 'Quickshell.exec() is not available in this Quickshell version\n' >&2
  grep -Rn 'Quickshell\.exec(' "$ROOT/shell/noxflow" \
    --include='*.qml' --include='*.js' --exclude-dir=tests >&2
  exit 1
fi
# noxd rejects ai_query (probed); the shell must not send it. Comments may
# name the rejected action to explain why it is not used.
if grep -Rn 'ai_query' "$ROOT/shell/noxflow" \
    --include='*.qml' --include='*.js' --exclude-dir=tests \
    | grep -vE ':[0-9]+: *//' >/dev/null; then
  printf 'ai_query is not a valid noxd action\n' >&2
  grep -Rn 'ai_query' "$ROOT/shell/noxflow" \
    --include='*.qml' --include='*.js' --exclude-dir=tests >&2
  exit 1
fi
# The shell unit has no ExecReload, so "reload" must never be used.
if grep -Rq '"reload", *"noxflow-shell' "$ROOT/shell/noxflow" \
    --include='*.qml' --include='*.js' --exclude-dir=tests; then
  printf 'noxflow-shell.service has no ExecReload; use restart\n' >&2
  exit 1
fi
# dunstctl has no get-paused subcommand.
if grep -Rq 'get-paused' "$ROOT/shell/noxflow" --exclude-dir=tests; then
  printf 'dunstctl get-paused is not a valid command; use is-paused\n' >&2
  exit 1
fi

# NF-08: Calculator returns structured result with valid/display/value fields
has 'function evaluateCalc' "$QML"
has 'display: "Invalid character"' "$QML"
has 'display: "Division by zero"' "$QML"
has 'display: "Unclosed parenthesis"' "$QML"
has 'display: "Trailing operators"' "$QML"
has 'valid: false, display: "?", value: ""' "$QML"

# NF-09: Desktop scan retry — retryScan function and scanFailed flag exist
has 'function retryScan()' "$QML"
has 'property bool scanFailed' "$QML"

# NF-19: Radial slotCount derived from slots.length so all geometry stays in sync
has 'readonly property int slotCount: Math.max(1, slots.length)' "$RADIAL"

printf 'noxflow launcher contract checks passed\n'
