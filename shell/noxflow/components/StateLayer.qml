// Material 3 state layer.
// Handles hover, pressed, dragged and focus overlays for interactive components.
// Connect: target.stateLayer.hovered = true when HoverHandler activates, etc.
// Stolen from Caelestia Shell's StateLayer.qml.

import QtQuick
import "../theme" as Theme

Rectangle {
    id: root

    /// The interactive item this layer tracks
    property Item target: parent

    /// Active state flags — set these externally from HoverHandler/TapHandler
    property bool hovered: false
    property bool pressed: false
    property bool focused: target ? target.activeFocus : false
    property bool disabled: target ? !target.enabled : false
    property bool dragged: false

    /// Override colours (null = use token defaults)
    property color hoverColor: Theme.Tokens.withAlpha(Theme.Tokens.stateHoverOverlay, 0.08)
    property color pressedColor: Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.12)
    property color focusColor: Theme.Tokens.withAlpha(Theme.Tokens.stateFocusOverlay, 0.12)
    property color dragColor: Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16)

    anchors.fill: target
    anchors.margins: -1
    radius: target ? (target.radius || Theme.Tokens.radiusSm) + 1 : Theme.Tokens.radiusSm + 1
    color: {
        if (!target || disabled) return "transparent"
        if (dragged) return dragColor
        if (pressed) return pressedColor
        if (hovered) return hoverColor
        if (focused) return focusColor
        return "transparent"
    }
    Behavior on color { ColorAnimation { duration: Theme.Tokens.duration(80) } }
    z: -1
}
