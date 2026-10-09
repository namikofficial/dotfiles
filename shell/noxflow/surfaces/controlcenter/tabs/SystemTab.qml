import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// System — CPU, memory and disk.
//
// Extracted from ControlCentre.qml, which was 1531 lines and mixed this tab
// with the host, the other six tabs, the tab bar and the Wi-Fi connect flow.
// The tab reaches the host through `host` instead of a dozen individually
// forwarded properties, so a new host property is reachable from here
// without touching this component.

Flickable {
    id: tabRoot

    // The owning ControlCentre. Every model and action used below lives
    // there; see the file header.
    required property var host
    anchors.fill: parent
    contentWidth: width
    contentHeight: systemContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 4
    interactive: contentHeight > height
    ColumnLayout {
        id: systemContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Text { text: "System Resources"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
        Text { text: !host.systemModel ? "Telemetry unavailable" : host.systemModel.status === "live" ? "Live · " + host.systemModel.dataSource : host.systemModel.status === "stale" ? "Stale · " + Math.round(host.systemModel.ageMs / 1000) + "s old · " + host.systemModel.dataSource : host.systemModel.status === "pending" ? "Waiting for telemetry" : "Telemetry unavailable"; color: host.systemModel && host.systemModel.status === "live" ? Theme.Tokens.stateSuccess : host.systemModel && host.systemModel.status === "stale" ? Theme.Tokens.stateWarning : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }

        // CPU
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: "CPU"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
            Components.Slider {
                Layout.fillWidth: true
                readOnly: true
                accessibleName: "CPU usage"
                value: (host.systemModel ? host.systemModel.cpuUsage : 0) / 100
                fillColor: (host.systemModel && host.systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
            }
            Text {
                text: host.systemModel && (host.systemModel.status === "live" || host.systemModel.status === "stale") ? Math.round(host.systemModel.cpuUsage) + "%" : "--"
                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                Layout.preferredWidth: 50
            }
        }

        // RAM
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: "RAM"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
            Components.Slider {
                Layout.fillWidth: true
                readOnly: true
                accessibleName: "Memory usage"
                value: (host.systemModel ? host.systemModel.memPercent : 0) / 100
                fillColor: (host.systemModel && host.systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
            }
            Text {
                text: host.systemModel && (host.systemModel.status === "live" || host.systemModel.status === "stale") ? (host.systemModel.memUsed / 1024 / 1024).toFixed(1) + "G/" + (host.systemModel.memTotal / 1024 / 1024).toFixed(1) + "G (" + Math.round(host.systemModel.memPercent) + "%)" : "--"
                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
            }
        }

        // Temperature
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: "Temp"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
            Item { Layout.fillWidth: true }
            Text {
                text: host.systemModel && (host.systemModel.status === "live" || host.systemModel.status === "stale") && host.systemModel.cpuTempAvailable ? Math.round(host.systemModel.cpuTemp) + "°C" : "Unavailable"
                color: (host.systemModel && host.systemModel.cpuTemp > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyBodySmall
            }
        }

        // GPU
        RowLayout {
            visible: !!host.systemModel && (host.systemModel.status === "live" || host.systemModel.status === "stale") && host.systemModel.gpuAvailable
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: host.systemModel && host.systemModel.gpuName ? host.systemModel.gpuName : "GPU"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.maximumWidth: 150 }
            Components.Slider {
                Layout.fillWidth: true
                readOnly: true
                accessibleName: "GPU usage"
                value: (host.systemModel ? host.systemModel.gpuUsage : 0) / 100
                fillColor: (host.systemModel && host.systemModel.gpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
            }
            Text { text: host.systemModel ? Math.round(host.systemModel.gpuUsage) + "%" : "--"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
        }

        // Disk
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: "Disk"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
            Components.Slider {
                Layout.fillWidth: true
                readOnly: true
                accessibleName: "Disk usage"
                value: (host.systemModel ? host.systemModel.diskPercent : 0) / 100
                fillColor: (host.systemModel && host.systemModel.diskPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
            }
            Text {
                text: host.systemModel && (host.systemModel.status === "live" || host.systemModel.status === "stale") ? (host.systemModel.diskUsed / 1024 / 1024).toFixed(1) + "G/" + (host.systemModel.diskTotal / 1024 / 1024).toFixed(1) + "G (" + Math.round(host.systemModel.diskPercent) + "%)" : "--"
                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
            }
        }
    }
}
