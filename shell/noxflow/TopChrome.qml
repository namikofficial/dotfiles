import QtQuick
import Quickshell
import Quickshell.Wayland
import "theme" as Theme

// The only top chrome layer. Bar and NoxIsland are ordinary child items so
// transparent pixels cannot create competing layer-surface hitboxes.
PanelWindow {
    id: root
    required property var screen
    required property var noxd
    required property var hyprland
    required property var audio
    required property var battery
    required property var network
    required property var bluetooth
    required property var media
    required property var notificationModel
    required property var systemModel
    required property var transfer
    required property var syncthing
    required property var brightness
    required property var updates
    required property var calModel
    required property var launcherComponent

    screen: root.screen
    anchors.top: true; anchors.left: true; anchors.right: true
    exclusiveZone: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    implicitHeight: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightToolbar), island.implicitHeight)
    color: "transparent"
    aboveWindows: true
    // The launcher must own keyboard input immediately, before any pointer
    // interaction. OnDemand/focusable only permits focus and does not reliably
    // transfer it on Hyprland, so request it explicitly while expanded.
    WlrLayershell.keyboardFocus: island.launcherVisible
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    Bar {
        id: bar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
        screen: root.screen
        noxd: root.noxd; hyprland: root.hyprland; audio: root.audio
        battery: root.battery; network: root.network; bluetooth: root.bluetooth
        media: root.media; notificationModel: root.notificationModel
        systemModel: root.systemModel; transfer: root.transfer; syncthing: root.syncthing
        updates: root.updates
        islandHost: island
    }

    NoxIsland {
        id: island
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        screen: root.screen
        noxd: root.noxd; audio: root.audio; brightness: root.brightness
        hyprland: root.hyprland
        battery: root.battery; network: root.network; bluetooth: root.bluetooth
        media: root.media; notificationModel: root.notificationModel; systemModel: root.systemModel
        transfer: root.transfer; syncthing: root.syncthing; updates: root.updates
        calModel: root.calModel
        launcherComponent: root.launcherComponent
        z: 10
    }

    // Observe taps anywhere in the current top-chrome input region without
    // stealing the child control's action. A tap outside the visible island
    // card dismisses a pin; taps inside the card remain interactive.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function(eventPoint) {
            var point = island.mapFromItem(root, eventPoint.position.x, eventPoint.position.y);
            island.clickAwayCheck(point);
        }
    }

    Component.onCompleted: shellRoot.registerIslandHost(root.screen, island)
    Component.onDestruction: shellRoot.unregisterIslandHost(root.screen)
}
