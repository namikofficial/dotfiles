import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Quick — summary tiles with network, Bluetooth, DND, brightness and volume.
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
    contentHeight: quickContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 0
    interactive: contentHeight > height
    ColumnLayout {
        id: quickContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Components.ControlTile {
            // The same wifi codepoint ConnectivityCapsule uses, so this matches
            // the bar. The old value was U+2301 (an electric arrow), which is not
            // in the icon font; both ternary branches were also identical, so
            // the condition never changed the result either way.
            icon: "\uF1EB"
            label: host.network.displayState
            subtitle: host.state.wifiActionState || (host.network.wifiEnabled === false ? "Enable Wi-Fi to connect" : host.state.wifiList().length + " networks visible")
            active: host.network.wifiUsable
            statusColor: host.network.connectivity === "full" ? Theme.Tokens.stateSuccess : host.network.connectivity === "limited" ? Theme.Tokens.stateWarning : Theme.Tokens.stateDanger
            onClicked: host.state.activeTab = 2
        }

        Components.ControlTile {
            // U+F294, matching ConnectivityCapsule's bluetooth glyph.
            icon: "\uF294"
            label: host.bluetooth.displayState
            subtitle: host.state.bluetoothActionState || host.state.bluetoothCountLabel()
            active: host.bluetooth.adapterPresent
            statusColor: host.bluetooth.powered ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
            onClicked: host.state.expandedSection = "bluetooth"
        }

        // Bluetooth details live in QuickBluetooth.qml; see that file's header
        // for why they were moved out.
        QuickBluetooth {
            host: tabRoot.host
        }

        Components.ControlTile {
            // A bell while notifications are allowed, a struck-through circle
            // once Do Not Disturb is on. U+F0F3 is the bell the bar pill uses.
            icon: host.state.focusEnabled ? "\uF056" : "\uF0F3"
            label: host.state.focusEnabled ? "Do Not Disturb (ON)" : "Do Not Disturb"
            active: true
            statusColor: host.state.focusEnabled ? Theme.Tokens.tonalPrimary : Theme.Tokens.textSecondary
            toggleChecked: host.state.focusEnabled
            showToggle: true
            Accessible.name: "Do Not Disturb"
            enabled: host.state.dndAvailable
            onToggleChanged: function(value) {
                if (!host.notificationModel) return;
                // setDnd, not toggleDnd: the toggle reports what
                // it wants, and idempotently so a stale tile
                // cannot flip the state the wrong way.
                host.notificationModel.setDnd(value);
            }
        }

        Text {
            visible: false
            text: ""
            color: Theme.Tokens.stateDanger
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Components.Divider { Layout.fillWidth: true }

        // Brightness
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingMd
            Text { text: "☼"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
            Components.Slider {
                Layout.fillWidth: true
                accessibleName: "Screen brightness"
                value: host.brightness.available ? host.brightness.percentage / 100 : 0.5
                onMoved: host.state.queueBrightness(value)
            }
            Text {
                text: Math.round(host.brightness.available ? host.brightness.percentage : 50) + "%"
                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
            }
        }

        // Volume
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingMd
            Text {
                // U+F026 muted / U+F028 volume — the same pair the bar's
                // audio capsule uses.
                text: host.audio.outputMuted ? "\uF026" : "\uF028"
                color: host.audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.tonalPrimary
                font.family: Theme.Tokens.iconFont
                font.pixelSize: Theme.Tokens.iconMd
                TapHandler { onTapped: { if (host.noxd.connected) host.noxd.runAction({ audio_toggle_mute: { target: "output" } }) } }
            }
            Components.Slider {
                Layout.fillWidth: true
                accessibleName: "Output volume"
                value: host.audio.available ? host.audio.outputVolume / host.audio.maxVolume : 0.5
                onMoved: host.state.queueVolume(value)
            }
            Text {
                text: host.audio.available ? host.audio.outputVolumePercent + "% · " + host.audio.outputName : "Audio unavailable"
                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
            }
        }

        Components.Divider { Layout.fillWidth: true }

        // Battery mode drawer
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingMd
            visible: host.power.profilesAvailable
            Text { text: "🔋"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
            Text {
                text: "Power profile"
                color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium
                Layout.fillWidth: true
            }
            Repeater {
                model: ["power-saver", "balanced", "performance"]
                delegate: Rectangle {
                    required property string modelData
                    height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                    implicitWidth: Theme.Tokens.scaled(70)
                    radius: Theme.Tokens.radiusPill
                    color: host.power.activeProfile === modelData ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceVariant
                    border.color: host.power.activeProfile === modelData ? Theme.Tokens.tonalPrimary : "transparent"
                    border.width: host.power.activeProfile === modelData ? 1 : 0
                    Text {
                        anchors.centerIn: parent
                        text: modelData === "power-saver" ? "🪫" : modelData === "balanced" ? "🔋" : "⚡"
                        color: host.power.activeProfile === modelData ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                    }
                    TapHandler { onTapped: { if (host.noxd.connected) host.noxd.runAction({ power_profile_set: { profile: modelData } }) } }
                }
            }
        }

        Components.Divider { Layout.fillWidth: true }

        // Power profile cycle
        RowLayout {
            Layout.fillWidth: true
            visible: host.power.profilesAvailable
            Text { text: "⚡"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
            Text {
                text: "Confirmed profile: " + (host.power.activeProfile || "Unknown")
                color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium
                Layout.fillWidth: true
            }
            Rectangle {
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                implicitWidth: Theme.Tokens.scaled(80)
                radius: Theme.Tokens.radiusPill
                color: Theme.Tokens.surfaceSurfaceVariant
                Text {
                    anchors.centerIn: parent
                    text: "Cycle"
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                }
                TapHandler {
                    onTapped: {
                        if (host.noxd.connected) {
                            var profiles = host.state.profileNames();
                            var idx = profiles.indexOf(host.power.activeProfile);
                            var next = profiles[(idx + 1) % profiles.length];
                            host.noxd.runAction({ power_profile_set: { profile: next } });
                        }
                    }
                }
            }
        }
    }
}
