import QtQuick
import "." as Local

// IslandCardHost.qml — binds IslandCard to the host's state.
//
// The card is the island's pixels and the host is its state machine, but the
// two were joined by a 54-line property-forwarding block sitting in the host
// file. That block was pure plumbing: it moved each host property onto the
// card and each card signal back into a host callback.
//
// This wrapper owns the forwarding in one place instead. `root` is the
// IslandHost, so every binding below reads exactly what the host read before —
// there is no second copy of the state, only one place that connects it to the
// view.

Local.IslandCard {
    id: card

    required property var root

    // ── State ──
    screen: card.root.screen
    islandState: card.root.islandState
    expanded: card.root.expanded
    visualExpanded: card.root.visualExpanded
    dashboardVisible: card.root.dashboardVisible
    launcherVisible: card.root.launcherVisible
    pinned: card.root.islandPinned
    reducedMotion: card.root.reducedMotion

    activityLabel: card.root.activityLabel
    activityValue: card.root.activityValue
    activityMaximum: card.root.activityMaximum
    displayPercent: card.root.displayPercent

    dashboardStatusVisible: card.root.dashboardStatusVisible
    dashboardStatusText: card.root.dashboardStatusText
    dashboardStatusValue: card.root.dashboardStatusValue
    dashboardStatusMaximum: card.root.dashboardStatusMaximum

    now: card.root.now
    activeApp: card.root.activeApp
    activeWin: card.root.activeWin

    pillWidth: card.root.pillW
    expandWidth: card.root.expandW

    // ── Models ──
    // The card reads the models directly, so the host passes them through
    // rather than re-deriving anything from them.
    hyprland: card.root.hyprland
    systemModel: card.root.systemModel
    network: card.root.network
    bluetooth: card.root.bluetooth
    audio: card.root.audio
    battery: card.root.battery
    notificationModel: card.root.notificationModel
    updates: card.root.updates

    // ── Callbacks ──
    onHoverEntered: card.root.cardHoverEntered()
    onHoverLeft: card.root.cardHoverLeft()
    onCardTapped: {
        if (card.root.islandState === "idle") card.root.openInlineCalendar();
        else card.root.openPanelFromIsland();
    }
    onPinClicked: card.root.pinToggle()
    onOpenClicked: card.root.openPanelFromIsland()
    onCloseClicked: card.root.dashboardClosed()
    onContextClicked: function (panel) { card.root.openPanelForKind(panel) }
}