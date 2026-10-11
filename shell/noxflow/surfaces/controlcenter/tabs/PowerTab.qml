import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Power — battery, power profiles and session actions.
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
    contentHeight: powerContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 6
    interactive: contentHeight > height
    ColumnLayout {
        id: powerContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Text { text: "Power & Battery"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }

        // Battery
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            visible: host.battery.available
            Text { text: host.battery.chargingState === "charging" ? "⚡" : host.battery.chargingState === "full" ? "🔋" : "🪫"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
            Item {
                // The percentage is painted on top of the bar, so the bar is
                // wrapped rather than replaced: a Slider cannot host the label.
                Layout.fillWidth: true
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                Components.Slider {
                    anchors.fill: parent
                    readOnly: true
                    accessibleName: "Battery level"
                    value: (host.battery.percentage || 0) / 100
                    fillColor: (host.battery.percentage || 0) > 20 ? Theme.Tokens.stateSuccess : Theme.Tokens.stateDanger
                }
                Text {
                    anchors.centerIn: parent
                    text: Math.round(host.battery.percentage || 0) + "%"
                    color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyLabelSmall
                    font.bold: true
                }
            }
        }

        Components.Divider { Layout.fillWidth: true; visible: host.power.profilesAvailable }

        // Power profiles
        Text {
            text: "Profile"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge
            visible: host.power.profilesAvailable
        }
        Repeater {
            model: host.state.profileNames()
            delegate: Rectangle {
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                radius: Theme.Tokens.radiusPill
                color: host.power.activeProfile === modelData ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceVariant
                border.color: host.power.activeProfile === modelData ? Theme.Tokens.tonalPrimary : "transparent"
                border.width: host.power.activeProfile === modelData ? 1 : 0
                Text {
                    anchors.centerIn: parent
                    text: modelData === "power-saver" ? "🪫 Power Saver" : modelData === "balanced" ? "🔋 Balanced" : "⚡ Performance"
                    color: host.power.activeProfile === modelData ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                    font.pixelSize: Theme.Tokens.typographyBodySmall
                }
                TapHandler { onTapped: { if (host.noxd.connected) host.noxd.runAction({ power_profile_set: { profile: modelData } }) } }
            }
        }
    }
}
