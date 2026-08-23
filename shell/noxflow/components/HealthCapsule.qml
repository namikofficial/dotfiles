import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
FocusScope {
    id: root
    required property var systemModel
    property bool ho: false
    property bool hovered: ho
    signal openSystem()
    readonly property bool ready: systemModel && systemModel.ready
    readonly property real temperature: ready ? Number(systemModel.cpuTemp || 0) : 0
    readonly property color temperatureColor: temperature >= 85 ? Theme.Tokens.stateDanger : temperature >= 75 ? Theme.Tokens.stateWarning : temperature >= 60 ? Theme.Tokens.tonalPrimary : Theme.Tokens.textSecondary
    readonly property string memoryLabel: ready ? (Number(systemModel.memUsed || 0) / 1048576).toFixed(1) + "G" : "—"
    implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), values.implicitWidth + Theme.Tokens.scaled(20))
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: ready ? "System health: CPU " + Math.round(systemModel.cpuUsage) + " percent, memory " + memoryLabel + ", temperature " + Math.round(temperature) + " degrees" : "System health unavailable"
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62); border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: root.activeFocus ? 2 : 0 }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        Text { text: "\uF2DB"; color: Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { text: root.ready ? Math.round(root.systemModel.cpuUsage) + "%" : "—"; color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
        Text { text: "\uE266"; color: Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { text: root.memoryLabel; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
        Text { text: "\uF2C9"; color: root.temperatureColor; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { text: root.temperature > 0 ? Math.round(root.temperature) + "°" : "—"; color: root.temperatureColor; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
    TapHandler { onTapped: root.openSystem() }
    Keys.onReturnPressed: root.openSystem()
    Keys.onSpacePressed: root.openSystem()
}
