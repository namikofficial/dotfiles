#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Phase 3 split the 1146-line NoxIsland.qml into island/. The host owns the
# state machine, the card owns the pixels and the layers own the calendar and
# launcher overlays; assert the contract against the file that now holds each
# behaviour rather than the deleted monolith.
island_dir="$root_dir/island"
island="$island_dir/IslandHost.qml"

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
# The split must stay split: the host is the state machine, the card the
# pixels, and the layers the calendar/launcher overlays.
grep -q 'IslandCard' "$island"
grep -q 'IslandLayers' "$island"
grep -q 'IslandRouter' "$island"
grep -q 'IslandEvents' "$island"
# `grep -r`, or these two passed vacuously: grep on a directory exits non-zero
# with "Is a directory" and the `!` turned that failure into a pass.
! grep -rq 'WheelHandler' "$island_dir"
! grep -rq 'Qt.MiddleButton' "$island_dir"
grep -q 'signal activityReady' "$root_dir/ActivityController.qml"

# ── OSD wiring: direction and single-producer ────────────────────────────────
# Three defects in a row made every volume, brightness and media OSD invisible
# while all 19 suites and `quickshell` load gates passed. qmllint cannot see any
# of them — they are runtime binding semantics — so they are asserted here.
#
# 1. Direction. IslandQueue and IslandEngagement *assign* the properties the
#    island renders from. Binding those down to them instead made every write
#    land on a bound property and vanish: after queue.show() the host still
#    reported currentKind "idle" and an empty label. Only properties a
#    component reads may be bound to it.
queue_host="$island_dir/IslandQueueHost.qml"
for mirrored in currentKind currentPriority currentStarted currentActivityId \
    activityLabel activityIcon activityValue activityMaximum expanded; do
    if grep -qE "^[[:space:]]*${mirrored}:[[:space:]]*wrapper\.root\.${mirrored}" "$queue_host"; then
        echo "island contract: $mirrored is bound down into IslandQueue, but the queue writes it" >&2
        exit 1
    fi
    grep -q "on${mirrored^}Changed: wrapper.root.${mirrored} = queue.${mirrored}" "$queue_host"
done
# The same mistake in the engagement machine: it assigns islandState,
# hoverExpanded and engagement, so those three cannot be bound down either.
# Scoped to the IslandEngagement block, because the sibling IslandState
# component legitimately reads `islandState` from the host.
engagement_block="$(sed -n '/Local\.IslandEngagement {/,/^    }$/p' "$island")"
[ -n "$engagement_block" ] || { echo 'island contract: no IslandEngagement block in the host' >&2; exit 1; }
if grep -qE '^[[:space:]]*(engagement|islandState|hoverExpanded):[[:space:]]*root\.' <<<"$engagement_block"; then
    echo 'island contract: IslandEngagement output is bound down into the machine' >&2
    exit 1
fi
grep -q 'onEngagementChanged: root.engagement = engagementState.engagement' "$island"
grep -q 'onIslandStateChanged: root.islandState = engagementState.islandState' "$island"
grep -q 'onHoverExpandedChanged: root.hoverExpanded = engagementState.hoverExpanded' "$island"

# 2. The card paints from islandState, so the OSD path has to set it. The
#    pre-split NoxIsland.display() assigned `islandState = entry.kind`; when
#    display() moved into IslandQueue, which owns only its own mirrors, that
#    assignment was lost and no card was ever painted.
grep -q 'root.islandState = activity.kind' "$island_dir/IslandEngagement.qml"

# 3. One producer per OSD dimension. The daemon event branch used to maintain
#    the same guard the model handler reads, and noxd delivers the event and
#    the model snapshot from the same publish, so the event always landed first
#    and the model handler always bailed out on its own guard test.
events="$island_dir/IslandEvents.qml"
! grep -q 'root.guardVolume = v' "$events"
! grep -q 'root.guardBrightness = b' "$events"
grep -q 'root.submit("volume", "Volume"' "$events"
grep -q 'root.submit("brightness", "Brightness"' "$events"

# 4. The same bound-down mistake in IslandLayers, which assigns all four of
#    these. With the writes stopping at the layer, the inline calendar never
#    expanded, `launcherVisible` never went true, and with it TopChrome's
#    keyboard focus and the launcher's Escape rule.
layers="$island_dir/IslandLayers.qml"
layers_block="$(sed -n '/Local\.IslandLayers {/,/^    }$/p' "$island")"
[ -n "$layers_block" ] || { echo 'island contract: no IslandLayers block in the host' >&2; exit 1; }
if grep -qE '^[[:space:]]*(calendarExpanded|launcherOpen|launcherClosing|launcherWasVisible):[[:space:]]*root\.' <<<"$layers_block"; then
    echo 'island contract: IslandLayers output is bound down into the layer' >&2
    exit 1
fi
grep -q 'onCalendarExpandedChanged: root.calendarExpanded = layers.calendarExpanded' "$island"

# 5. TopChrome sizes its window to `max(heightToolbar, island.implicitHeight)`,
#    so this binding is the only thing that makes room for the dashboard, the
#    calendar and the launcher. The split dropped it and left the `Behavior on
#    implicitHeight` animating a property nobody assigned: the island window
#    stayed 44px tall and every expanded surface was clipped to the bar.
grep -qE '^[[:space:]]*implicitHeight:[[:space:]]*launcherVisible' "$island"
grep -q 'Theme.Tokens.islandIdleHeight' "$island"

# 6. CalendarWidget runs its own SurfaceLifecycle: its body is
#    `opacity: openProgress` and it is `visible: lifecycle.active`, both zero
#    until open() is called. These calls were dropped with the rest.
grep -q 'calendarWidget.open()' "$layers"
grep -q 'calendarWidget.close()' "$layers"

printf '%s\n' 'noxflow island component contract passed'
