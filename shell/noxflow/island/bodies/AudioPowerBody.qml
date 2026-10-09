import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// AudioPowerBody.qml — island dashboard for output, input and battery.



ColumnLayout {
    id: root

    property var audio: null
    property var battery: null

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    readonly property bool hasBattery: !!(battery && battery.present)
    readonly property var remainingSeconds: {
        if (!root.battery) return null;
        if (root.battery.timeToEmptySeconds) return root.battery.timeToEmptySeconds;
        if (root.battery.timeToFullSeconds) return root.battery.timeToFullSeconds;
        return null;
    }

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: root.audio
            ? "Output  " + (root.audio.outputMuted ? "Muted" : root.audio.outputVolumePercent + "%")
            : "Audio unavailable"
        headlineColor: root.audio && root.audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary
        details: {
            var rows = [];
            if (root.audio) {
                rows.push({ text: root.audio.outputName || "Default output" });
                rows.push({
                    text: "Microphone  " + (root.audio.inputMuted
                        ? "Muted" : root.audio.inputVolumePercent + "%"),
                    color: root.audio.inputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary
                });
            }
            if (root.hasBattery) {
                rows.push({
                    text: "Battery  " + Math.round(root.battery.percentage || 0) + "%  ·  "
                        + root.battery.chargingState,
                    emphasis: true,
                    bold: true,
                    color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                });
                rows.push({
                    text: "Health  " + (root.battery.healthPercentage !== null && root.battery.healthPercentage !== undefined
                            ? Math.round(root.battery.healthPercentage) + "%" : "unavailable")
                        + "  ·  remaining time  " + (root.remainingSeconds !== null
                            ? Math.round(root.remainingSeconds / 60) + " min" : "unavailable")
                });
            }
            return rows;
        }
        footnote: root.hasBattery ? "" : "No battery is present on this machine."
    }
}