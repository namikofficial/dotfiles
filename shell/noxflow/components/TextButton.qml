import QtQuick
import "../theme" as Theme

FocusScope {
    id: root
    property string text: "Button"
    property string accessibleName: root.text
    property bool hovered: false
    property bool pressed: false
    signal clicked()
    implicitWidth: label.implicitWidth + Theme.Tokens.spacingXl
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightButton)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled

    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: root.pressed ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16) : root.hovered ? Theme.Tokens.withAlpha(Theme.Tokens.stateHoverOverlay, 0.10) : Theme.Tokens.tonalPrimaryContainer; border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: root.activeFocus ? 2 : 0 }
    Text { id: label; anchors.centerIn: parent; text: root.text; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelLarge; font.family: Theme.Tokens.typographyFontFamily }
    HoverHandler { onHoveredChanged: root.hovered = hovered }
    TapHandler { onTapped: if (root.enabled) root.clicked() }
    Keys.onSpacePressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
}
