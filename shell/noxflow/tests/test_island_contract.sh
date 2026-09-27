#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
island="$root_dir/NoxIsland.qml"

for source in workspace health connectivity audio-power notification-preview updates sync provider-health; do
    grep -q "\"$source\"" "$root_dir/HoverEngagement.js"
done
for mode in idle activity dashboard launcher calendar; do
    grep -q "\"$mode\"" "$root_dir/ActivityArbitration.js"
done
for action in "Pin dashboard" "Open full panel" "Close dashboard"; do
    grep -q "$action" "$root_dir/surfaces/island/IslandHeaderActions.qml"
done
grep -q 'implicitWidth: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)' "$root_dir/components/IconButton.qml"
grep -q 'islandHoverDwell: 140' "$root_dir/theme/Tokens.qml"
grep -q 'islandTransitGrace: 450' "$root_dir/theme/Tokens.qml"
! grep -q 'WheelHandler' "$island"
! grep -q 'Qt.MiddleButton' "$island"
grep -q 'required property var activityController' "$island"
grep -q 'signal activityReady' "$root_dir/ActivityController.qml"

printf '%s\n' 'noxflow island component contract passed'
