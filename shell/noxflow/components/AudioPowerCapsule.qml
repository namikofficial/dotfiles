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
    readonly property bool batteryReady: battery && battery.status === "available" && battery.present && battery.percentage !== null
    readonly property bool charging: batteryReady && (battery.chargingState === "charging" || battery.acOnline === true)
    implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), values.implicitWidth + Theme.Tokens.scaled(20))
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Audio " + (audio.outputMuted ? "muted" : audio.outputVolumePercent + " percent") + (batteryReady ? ", battery " + Math.round(battery.percentage) + " percent" : "")
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62); border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: root.activeFocus ? 2 : 0 }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        Text { text: root.audio.outputMuted ? "\uF026" : "\uF028"; color: root.audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { visible: !root.audio.outputMuted; text: String(root.audio.outputVolumePercent); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
        Rectangle { visible: root.batteryReady; width: 1; height: Theme.Tokens.scaled(14); color: Theme.Tokens.outlineSubtle }
        Text { visible: root.batteryReady; text: root.charging ? "\uF1E6" : root.battery.critical ? "\uF244" : "\uF240"; color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs; TapHandler { onTapped: root.openPower() } }
        Text { visible: root.batteryReady; text: Math.round(root.battery.percentage); color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium; TapHandler { onTapped: root.openPower() } }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: root.toggleMute() }
    WheelHandler { onWheel: function(event) { root.adjustVolume(event.angleDelta.y > 0 ? 5 : -5); event.accepted = true; } }
    Keys.onReturnPressed: root.toggleMute()
    Keys.onSpacePressed: root.toggleMute()
}
