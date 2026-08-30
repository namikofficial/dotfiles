import QtQuick
import "../theme" as Theme

FocusScope {
    id: root
    property bool checked: false
    property bool hovered: false
    property bool pressed: false
    property string accessibleName: "Toggle"
    signal toggled(bool value)
    implicitWidth: 52
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightControl)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled
    scale: pressed ? 0.96 : hovered ? 1.02 : 1.0
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checked: root.checked
    Rectangle { anchors.centerIn: parent; width: 52; height: 32; radius: 16; color: root.pressed ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16) : root.checked ? Theme.Tokens.tonalPrimary : Theme.Tokens.surfaceSurfaceVariant; border.color: root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineDefault; border.width: root.activeFocus ? 2 : 1 }
    Rectangle { x: root.checked ? 27 : 5; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11; color: root.checked ? Theme.Tokens.tonalOnPrimary : Theme.Tokens.textMuted; Behavior on x { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } } }
    Behavior on scale { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
    HoverHandler { onHoveredChanged: root.hovered = hovered }
    TapHandler {
        onPressedChanged: root.pressed = pressed
        onTapped: {
            if (!root.enabled) return;
            root.forceActiveFocus();
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
    Keys.onSpacePressed: {
        if (root.enabled) { root.checked = !root.checked; root.toggled(root.checked); }
    }
    Keys.onReturnPressed: {
        if (root.enabled) { root.checked = !root.checked; root.toggled(root.checked); }
    }
}
