import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
FocusScope {
    id: root
    required property var systemModel

    // Maps the SystemModel's freshness status to a short, accessible phrase.
    // The capsule stays visually compact but the accessible name always
    // discloses whether the numbers below are live, stale, or unavailable —
    // it must never present stale telemetry as a fresh reading.
    readonly property string freshness: !systemModel ? "pending"
        : systemModel.status === "stale" ? "stale"
        : systemModel.status === "unavailable" ? "unavailable"
        : systemModel.status === "pending" ? "pending"
        : "live"
    readonly property bool ready: freshness === "live" || freshness === "stale"
    readonly property int ageSeconds: systemModel && systemModel.ageMs > 0
        ? Math.round(systemModel.ageMs / 1000) : -1
    readonly property string freshnessLabel: freshness === "pending" ? "waiting"
        : freshness === "live" ? "live"
        : freshness === "stale" ? ("stale " + ageSeconds + "s")
        : "unavailable"

    property bool ho: false
    property bool hovered: ho
    signal openSystem()

    // CPU temperature only renders when the parser flagged it as available
    // and as positive. When unavailable, the em dash (—) is honest.
    readonly property real temperature: (ready && systemModel.cpuTempAvailable && systemModel.cpuTemp > 0)
        ? Number(systemModel.cpuTemp) : 0
    readonly property color temperatureColor: !ready || temperature <= 0 ? Theme.Tokens.textSecondary
        : temperature >= 85 ? Theme.Tokens.stateDanger
        : temperature >= 75 ? Theme.Tokens.stateWarning
        : temperature >= 60 ? Theme.Tokens.tonalPrimary
        : Theme.Tokens.textSecondary
    readonly property string memoryLabel: ready ? (Number(systemModel.memUsed || 0) / 1048576).toFixed(1) + "G" : "—"
    readonly property string cpuLabel: ready ? Math.round(systemModel.cpuUsage) + "%" : "—"
    readonly property string temperatureLabel: temperature > 0 ? Math.round(temperature) + "°" : "—"

    implicitWidth: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: {
        if (!systemModel) return "System health unavailable";
        if (freshness === "pending") return "System health not yet ready";
        if (freshness === "unavailable") return "System health unavailable: " + (systemModel.lastError || "no data");
        var src = systemModel.dataSource || "proc";
        var cpu = "CPU " + Math.round(systemModel.cpuUsage) + " percent";
        var mem = "memory " + memoryLabel;
        var therm = systemModel.cpuTempAvailable
            ? ", temperature " + Math.round(systemModel.cpuTemp) + " degrees"
            : ", temperature unavailable";
        var source = src === "proc" ? "from /proc and /sys"
            : src === "proc+nvidia" ? "from /proc and NVIDIA"
            : src === "proc+integrated" ? "from /proc and integrated GPU"
            : "from system";
        var stale = freshness === "stale" ? ", data is " + ageSeconds + " seconds old" : "";
        return "System health " + freshnessLabel + ": " + cpu + ", " + mem + therm + ", " + source + stale;
    }

    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: root.hovered ? Theme.Tokens.surfaceSurfaceHighest : "transparent"; border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: root.activeFocus ? 2 : 0 }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        Text { text: "\uF2DB"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.iconFont; font.pixelSize: Theme.Tokens.iconXs }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
    TapHandler { onTapped: root.openSystem() }
    Keys.onReturnPressed: root.openSystem()
    Keys.onSpacePressed: root.openSystem()
}
