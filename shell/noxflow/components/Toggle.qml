import QtQuick
import "../theme" as Theme

FocusScope {
    id: root

    // Controlled component contract: callers bind checked to their state.
    // User interaction emits toggled(newValue) signal WITHOUT mutating checked.
    // The binding source updates checked, which drives the visual state.
    // This avoids binding loops when callers bind checked to provider/token state.
    property bool checked: false
    property bool hovered: false
    property bool pressed: false
    property string accessibleName: "Toggle"
    signal toggled(bool value)
    implicitWidth: Theme.Tokens.scaled(Theme.Tokens.widthSwitchTrack)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightControl)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled
    scale: pressed ? 0.96 : hovered ? 1.02 : 1.0
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checked: root.checked
    // Every dimension below is derived from Tokens. This used to hardcode
    // 52 x 32 for the track, a 22px knob and x positions of 5 / 27, so the
    // switch could not follow a density or scale change with anything else.
    readonly property int trackHeight: Theme.Tokens.scaled(Theme.Tokens.heightSwitchTrack)
    readonly property int trackWidth: Theme.Tokens.scaled(Theme.Tokens.widthSwitchTrack)
    readonly property int knobSize: Theme.Tokens.scaled(Theme.Tokens.sizeSwitchKnob)
    // Inset between the knob and the track end, both states.
    readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
    readonly property real knobOnX: trackWidth - knobInset - knobSize
    Rectangle {
        anchors.centerIn: parent
        width: root.trackWidth; height: root.trackHeight
        radius: Math.round(root.trackHeight / 2)
        color: root.pressed ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16) : root.checked ? Theme.Tokens.tonalPrimary : Theme.Tokens.surfaceSurfaceVariant
        border.color: root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineDefault
        border.width: root.activeFocus ? 2 : 1
        Behavior on color { ColorAnimation { duration: Theme.Tokens.durationShort } }
    }
    Rectangle {
        x: root.checked ? root.knobOnX : root.knobInset
        anchors.verticalCenter: parent.verticalCenter
        width: root.knobSize; height: root.knobSize
        radius: Math.round(root.knobSize / 2)
        color: root.checked ? Theme.Tokens.tonalOnPrimary : Theme.Tokens.textMuted
        Behavior on x { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
    }
    Behavior on scale { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
    HoverHandler { onHoveredChanged: root.hovered = hovered }
    TapHandler {
        onPressedChanged: root.pressed = pressed
        onTapped: {
            if (!root.enabled) return;
            root.forceActiveFocus();
            // Emit the toggled signal with the requested new value.
            // Do NOT assign to checked here — that is the caller's responsibility
            // via the binding. This prevents binding-loop-prone checked mutation.
            root.toggled(!root.checked);
        }
    }
    Keys.onSpacePressed: {
        if (root.enabled) { root.forceActiveFocus(); root.toggled(!root.checked); }
    }
    Keys.onReturnPressed: {
        if (root.enabled) { root.forceActiveFocus(); root.toggled(!root.checked); }
    }
}
