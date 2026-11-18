import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
import "../components" as Components

// BarStatusPill.qml — shared chrome for every bar pill.
//
// Before this existed, each pill re-declared its own glass rectangle, hover
// handler, press state and focus border, and they had drifted: one pill used
// `ho`, another `hovered`, a third neither, which is why the updates tooltip
// never appeared (Tooltip.qml binds `target.hovered`).
//
// A pill declares content and behaviour; this component owns the appearance.



FocusScope {
    id: root

    // ── Presentation ──
    property bool active: false
    property bool occupied: false
    property bool urgent: false
    property bool failed: false
    property bool danger: false
    // Workspace controls live inside one shared rail track. Their inactive
    // states stay open so the active workspace, rather than a row of little
    // cards, carries the visual weight.
    property bool railItem: false

    // ── Behaviour ──
    signal tapped()
    signal secondaryTapped()
    signal hoverChanged(bool hovered)

    // ── Content ──
    default property alias content: contentRow.data

    property real horizontalPadding: Theme.Tokens.scaled(12)
    property int minimumWidth: 0
    property string tooltipText: ""

    property bool hovered: hoverHandler.hovered
    property bool pressed: tapHandler.pressed

    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    implicitWidth: Math.max(minimumWidth, contentRow.implicitWidth + horizontalPadding * 2)
    Layout.alignment: Qt.AlignVCenter
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText

    Rectangle {
        anchors.fill: parent
        radius: root.railItem ? Theme.Tokens.radiusMd : Theme.Tokens.radiusPill
        color: root.railItem
            ? (root.active
                ? Theme.Tokens.tonalPrimary
                : root.pressed
                    ? Theme.Tokens.surfaceSurfaceHighest
                    : root.hovered
                        ? Theme.Tokens.surfaceSurface2
                        : "transparent")
            : root.failed
                ? Theme.Tokens.glass(Theme.Tokens.stateDanger, 0.34)
                : root.pressed
                    ? Theme.Tokens.tonalPrimaryContainer
                    : root.active
                        ? Theme.Tokens.tonalPrimary
                        : root.hovered
                            ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78)
                            : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
        border.color: root.activeFocus
            ? Theme.Tokens.outlineFocus
            : root.active
                ? (root.railItem ? "transparent" : Theme.Tokens.tonalPrimary)
                : "transparent"
        border.width: root.active && !root.railItem ? 1 : (root.activeFocus ? 2 : 0)
        // Unoccupied pills recede so the active workspace reads first.
        opacity: root.railItem ? 1.0 : root.active ? 1.0 : root.occupied ? 0.85 : 0.55
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: Theme.Tokens.scaled(5)
    }

    // Urgent marker, top-right. Separate from the row so it never affects the
    // pill's measured width.
    Rectangle {
        visible: root.urgent
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        width: 6
        height: 6
        radius: 3
        color: Theme.Tokens.stateDanger
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: root.hoverChanged(hovered)
    }
    TapHandler {
        id: tapHandler
        onTapped: root.tapped()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.secondaryTapped()
    }
    Keys.onReturnPressed: root.tapped()
    Keys.onSpacePressed: root.tapped()

    Components.Tooltip {
        target: root
        text: root.tooltipText
    }
}
