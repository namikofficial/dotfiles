import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
import "../WorkspacePresentation.js" as Presentation
import "." as Local

// WorkspacePill.qml — one workspace in the bar's left zone.
//
// Presentation rules live in WorkspacePresentation.js (shared with the island);
// this component is the view. Appearance comes from BarStatusPill.



Local.BarStatusPill {
    id: root

    // Named with an `is` prefix: `active` and `pressed` are already owned by
    // BarStatusPill, and a property of the same name bound to itself is a
    // silent no-op rather than an error.
    property bool isActive: false
    property bool isOccupied: false
    property bool isUrgent: false
    property bool hasActiveWindow: false
    property string activeApp: ""
    property string activeTitle: ""

    required property string workspaceName

    signal activated(string name)
    signal cycled(int direction)

    // Set by WorkspaceCluster so a pill hover can reach the island without this
    // component having to know about NoxIsland.
    property var hoverSource: null

    active: root.isActive
    occupied: root.isOccupied
    urgent: root.isUrgent
    tooltipText: Presentation.tooltip(root.workspaceName, root.isActive, root.isOccupied,
                                      root.activeApp, root.activeTitle)

    onTapped: root.activated(root.workspaceName)
    onSecondaryTapped: root.activated(root.workspaceName)
    onHoverChanged: function(hovered) {
        if (root.hoverSource) root.hoverSource(root.workspaceName, hovered, root);
    }

    Text {
        text: root.workspaceName
        color: root.isActive ? Theme.Tokens.tonalOnPrimary
                             : root.isOccupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyLabelMedium
        font.bold: root.isActive
    }
    Text {
        visible: root.hasActiveWindow
        text: ""
        color: Theme.Tokens.tonalOnPrimary
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.typographyLabelSmall
    }
    Text {
        visible: root.hasActiveWindow && root.activeApp !== ""
        text: root.activeApp
        color: Theme.Tokens.tonalOnPrimary
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyLabelSmall
        font.bold: true
        elide: Text.ElideRight
        Layout.maximumWidth: Theme.Tokens.scaled(96)
    }

    // No WheelHandler here: BarStatusPill is a FocusScope, and a wheel
    // handler can only attach to an Item. The cluster — an Item — owns the
    // scroll instead.
    Keys.onLeftPressed: root.cycled(-1)
    Keys.onRightPressed: root.cycled(1)
}