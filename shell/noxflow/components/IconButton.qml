import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

FocusScope {
    id: root
    property string iconText: "•"
    property string accessibleName: "Icon button"
    property bool checked: false
    property bool hovered: false
    property bool pressed: false
    signal clicked()
    implicitWidth: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.Tokens.radiusPill
        color: root.pressed ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16) : root.hovered ? Theme.Tokens.withAlpha(Theme.Tokens.stateHoverOverlay, 0.10) : root.checked ? Theme.Tokens.tonalPrimaryContainer : "transparent"
        border.color: root.activeFocus ? Theme.Tokens.outlineFocus : root.checked ? Theme.Tokens.tonalPrimary : "transparent"
        border.width: root.activeFocus || root.checked ? 1 : 0
    }
    Text { anchors.centerIn: parent; text: root.iconText; color: root.checked ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.iconMd }
    HoverHandler { onHoveredChanged: root.hovered = hovered }
    TapHandler { onTapped: if (root.enabled) root.clicked() }
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
}
