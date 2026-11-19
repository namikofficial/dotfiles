#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ATLAS="$ROOT/shell/noxflow/surfaces/atlas/Atlas.qml"
WORKSPACE="$ROOT/shell/noxflow/surfaces/atlas/AtlasWorkspace.qml"
WINDOW="$ROOT/shell/noxflow/surfaces/atlas/AtlasWindow.qml"
SHELL="$ROOT/shell/noxflow/shell.qml"

has() {
  local needle="$1" file="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'missing %s in %s\n' "$needle" "$file" >&2
    exit 1
  fi
}

has 'hyprlandModel: hyprlandModel' "$SHELL"
has 'function rememberFocusedWindow(window)' "$ATLAS"
has 'function onActiveWindowChanged()' "$ATLAS"
has 'RECENT FOCUS' "$ATLAS"
has 'root.focusRecent(modelData)' "$ATLAS"
has 'Keys.onReturnPressed' "$WORKSPACE"
has 'Keys.onSpacePressed' "$WORKSPACE"
has 'function moveWindow(address, workspace)' "$ATLAS"
has 'workspaceGrid.count <= 1' "$ATLAS"
has 'movetoworkspacesilent ' "$ATLAS"
has 'DropArea {' "$WORKSPACE"
has 'drop.source.address' "$WORKSPACE"
has 'Drag.active: dragHandler.active' "$WINDOW"
has 'Drag.source: root' "$WINDOW"
has 'DragHandler {' "$WINDOW"

printf 'noxflow Atlas contract checks passed\n'
