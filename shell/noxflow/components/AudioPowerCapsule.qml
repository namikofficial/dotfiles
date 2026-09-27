import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
FocusScope {
    id: root
    required property var audio
    required property var battery
    property bool ho: false
    property bool hovered: ho
    signal toggleMute()
    signal adjustVolume(int delta)
    signal openPower()
    property alias audioActionItem: audioAction
    property alias powerActionItem: powerAction
    readonly property bool batteryReady: battery && battery.status === "available" && battery.present && battery.percentage !== null
    readonly property bool charging: batteryReady && (battery.chargingState === "charging" || battery.acOnline === true)
    implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), values.implicitWidth + Theme.Tokens.scaled(24))
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        FocusScope {
            id: audioAction
            activeFocusOnTab: true
            implicitWidth: audioValues.implicitWidth + Theme.Tokens.scaled(8)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            Accessible.role: Accessible.Button
            Accessible.name: "Audio " + (root.audio.outputMuted ? "muted" : root.audio.outputVolumePercent + " percent")
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: audioAction.activeFocus ? Theme.Tokens.glass(Theme.Tokens.outlineFocus, 0.20) : "transparent"; border.color: audioAction.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: audioAction.activeFocus ? 2 : 0 }
            RowLayout {
                id: audioValues
                anchors.centerIn: parent
                spacing: Theme.Tokens.scaled(6)
                Text { text: root.audio.outputMuted ? "\uF026" : "\uF028"; color: root.audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
                Text { visible: !root.audio.outputMuted; text: String(root.audio.outputVolumePercent); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
            }
            TapHandler { onTapped: { audioAction.forceActiveFocus(); root.toggleMute(); } }
            WheelHandler { onWheel: function(event) { root.adjustVolume(event.angleDelta.y > 0 ? 5 : -5); event.accepted = true; } }
            Keys.onReturnPressed: root.toggleMute()
            Keys.onSpacePressed: root.toggleMute()
        }
        Rectangle { visible: root.batteryReady; width: 1; height: Theme.Tokens.scaled(14); color: Theme.Tokens.outlineSubtle }
        FocusScope {
            id: powerAction
            visible: root.batteryReady
            activeFocusOnTab: visible
            implicitWidth: powerValues.implicitWidth + Theme.Tokens.scaled(8)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            Accessible.role: Accessible.Button
            Accessible.name: root.batteryReady ? "Battery " + Math.round(root.battery.percentage) + " percent. Open power settings" : "Power unavailable"
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: powerAction.activeFocus ? Theme.Tokens.glass(Theme.Tokens.outlineFocus, 0.20) : "transparent"; border.color: powerAction.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: powerAction.activeFocus ? 2 : 0 }
            RowLayout {
                id: powerValues
                anchors.centerIn: parent
                spacing: Theme.Tokens.scaled(6)
                Text { text: root.charging ? "\uF1E6" : root.battery.critical ? "\uF244" : "\uF240"; color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
                Text { text: Math.round(root.battery.percentage); color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
            }
            TapHandler { onTapped: { powerAction.forceActiveFocus(); root.openPower(); } }
            Keys.onReturnPressed: root.openPower()
            Keys.onSpacePressed: root.openPower()
        }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
}
