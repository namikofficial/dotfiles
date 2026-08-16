#!/usr/bin/env bash
set -euo pipefail

# Static regression checks for the Super+Space launcher contract.  These tests
# deliberately inspect the source instead of opening a graphical session, so
# they can run in CI and on recovery consoles.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QML="$ROOT/shell/noxflow/surfaces/launcher/Launcher.qml"
ISLAND="$ROOT/shell/noxflow/NoxIsland.qml"
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

# Super+Space must be hosted by the existing Dynamic Island. A launcher entry
# in MorphSurface would create a second layer window and regress the morph.
has 'launcherVisible' "$ISLAND"
has 'sourceComponent: root.launcherComponent' "$ISLAND"
has 'height: parent.height' "$ISLAND"
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

printf 'noxflow launcher contract checks passed\n'
