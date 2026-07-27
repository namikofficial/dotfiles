// Material 3 elevation/shadow effect.
// Stolen from Caelestia Shell's Elevation.qml pattern.
// Maps token elevation levels to visual depth (border + blur separation).

import QtQuick
import "../theme" as Theme

Item {
    id: root

    /// The elevation level: 0-4 (none, low, medium, high, overlay)
    property int level: 0

    /// The child surface this elevation wraps
    default property alias data: surface.data

    /// Whether to render a visible border at the edges
    property bool showBorder: level > 0

    /// Reference to the rendered rectangle (for external styling)
    property alias surface: surface

    implicitWidth: surface.implicitWidth
    implicitHeight: surface.implicitHeight

    Rectangle {
        id: surface
        anchors.fill: parent
        color: Theme.Tokens.surfaceSurface
        radius: Theme.Tokens.radiusLg
        border.color: root.showBorder ? Theme.Tokens.outlineSubtle : "transparent"
        border.width: root.showBorder ? 1 : 0

        // Simulated depth via layered background
        property color depthColor: {
            switch (root.level) {
                case 1: return Qt.rgba(0, 0, 0, 0.05)
                case 2: return Qt.rgba(0, 0, 0, 0.08)
                case 3: return Qt.rgba(0, 0, 0, 0.11)
                case 4: return Qt.rgba(0, 0, 0, 0.14)
                default: return "transparent"
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: parent.depthColor
        }
    }
}
