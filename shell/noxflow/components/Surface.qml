import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    property color tonalColor: Theme.Tokens.surfaceSurface
    property color contentColor: Theme.Tokens.textPrimary
    property int cornerRadius: Theme.Tokens.radiusLg
    property int elevationLevel: Theme.Tokens.elevationNone
    property bool interactive: false
    property bool hovered: false
    property bool pressed: false
    color: root.tonalColor
    radius: root.cornerRadius
    border.color: root.elevationLevel > 0 ? Theme.Tokens.outlineSubtle : "transparent"
    border.width: root.elevationLevel > 0 ? 1 : 0
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled

    states: State {
        name: "hovered"
        when: root.interactive && root.hovered && root.enabled
        PropertyChanges { target: root; color: Theme.Tokens.withAlpha(root.tonalColor, 0.92) }
    }
}
