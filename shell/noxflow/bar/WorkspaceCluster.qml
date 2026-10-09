import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
import "." as Local

// WorkspaceCluster.qml — the horizontally scrollable workspace strip.
//
// Owns the scroller, the pill list, and the hover/activation wiring. The bar
// only supplies the derived state and the callbacks.



Item {
    id: root

    required property var entries
    // Per-workspace derived state, keyed by workspace name. Supplied by the
    // bar so the cluster stays free of hyprland knowledge.
    required property var presentation
    required property var monitorName

    signal activated(string name)
    signal cycled(int direction)
    signal hovered(string name, bool isHovered, var pill)

    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    // The strip grows with its content up to a cap, then scrolls. Without the
    // cap a heavily-used monitor pushes the right zone off screen.
    implicitWidth: Math.min(contents.implicitWidth, Theme.Tokens.scaled(360))

    // Wheel over the strip cycles workspaces. It lives on the cluster because
    // the pill itself is a FocusScope (a BarStatusPill) and cannot take a
    // WheelHandler.
    WheelHandler {
        id: cycleWheel
        onWheel: function (event) {
            root.cycled(event.angleDelta.y > 0 ? -1 : 1);
            event.accepted = true;
        }
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: contents.implicitWidth
        contentHeight: height
        // The scroller decides whether it is *interactive*, not whether it is
        // *visible*. `visible: contentWidth > width` hid the whole workspace
        // strip whenever the content happened to fit — which is the normal
        // case on a laptop — so the bar showed no workspaces at all.
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        pressDelay: 80

        RowLayout {
            id: contents
            spacing: Theme.Tokens.scaled(Theme.Tokens.spacingSm)
            height: scroller.height

            Repeater {
                model: root.entries

                delegate: Local.WorkspacePill {
                    required property var modelData
                    required property int index

                    workspaceName: String(modelData)
                    isActive: root.presentation(modelData).active
                    isOccupied: root.presentation(modelData).occupied
                    isUrgent: root.presentation(modelData).urgent
                    hasActiveWindow: root.presentation(modelData).hasActiveWindow
                    activeApp: root.presentation(modelData).activeApp
                    activeTitle: root.presentation(modelData).activeTitle

                    hoverSource: function (name, isHovered, pill) {
                        root.hovered(name, isHovered, pill);
                    }
                    onActivated: function (name) { root.activated(name); }
                    onCycled: function (direction) { root.cycled(direction); }
                }
            }
        }
    }
}