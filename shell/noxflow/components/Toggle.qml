import QtQuick
import "../theme" as Theme

FocusScope {
    id: root
    property bool checked: false
    property bool hovered: false
    signal toggled(bool value)
    implicitWidth: 52
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightControl)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled
    Rectangle { anchors.centerIn: parent; width: 52; height: 32; radius: 16; color: root.checked ? Theme.Tokens.tonalPrimary : Theme.Tokens.surfaceSurfaceVariant; border.color: root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineDefault; border.width: root.activeFocus ? 2 : 1 }
    Rectangle { x: root.checked ? 27 : 5; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11; color: root.checked ? Theme.Tokens.tonalOnPrimary : Theme.Tokens.textMuted }
    HoverHandler { onHoveredChanged: root.hovered = hovered }
    TapHandler { onTapped: if (root.enabled) { root.checked = !root.checked; root.toggled(root.checked) } }
    Keys.onSpacePressed: if (root.enabled) { root.checked = !root.checked; root.toggled(root.checked) }
}
