import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Input — microphone, keyboard and touchpad.
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
    contentHeight: inputContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 5
    interactive: contentHeight > height
    ColumnLayout {
        id: inputContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Text { text: "Input"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }

        // Mic volume
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text {
                text: host.audio.inputMuted ? "⊗" : "◌"
                color: host.audio.inputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.tonalPrimary
                font.pixelSize: Theme.Tokens.iconMd
                TapHandler { onTapped: { if (host.noxd.connected) host.noxd.runAction({ audio_toggle_mute: { target: "input" } }) } }
            }
            Components.Slider {
                Layout.fillWidth: true
                accessibleName: "Microphone volume"
                value: host.audio.available ? host.audio.inputVolume / host.audio.maxVolume : 0.5
                onMoved: function(value) {
                    if (host.audio.available && host.noxd.connected)
                        host.noxd.runAction({ audio_set_volume: { target: "input", volume: Math.round(value * host.audio.maxVolume) } });
                }
            }
        }

        // Input devices
        Text { text: "Input Devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
        Repeater {
            model: host.audio.inputs
            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 100
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                radius: Theme.Tokens.radiusSm
                color: modelData.active ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                border.color: modelData.active ? Theme.Tokens.tonalPrimary : "transparent"
                border.width: modelData.active ? 1 : 0
                RowLayout {
                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm
                    Text { text: "◌"; color: modelData.active ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                    Text {
                        text: modelData.description || modelData.name || "Unknown"
                        elide: Text.ElideRight; Layout.fillWidth: true
                        color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                }
                TapHandler {
                    onTapped: {
                        if (host.noxd.connected)
                            host.noxd.runAction({ audio_set_default: { target: "input", selector: modelData.name || modelData.description } })
                    }
                }
            }
        }

        // Keyboard layout
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
            Text { text: "⌨"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
            Text {
                text: host.systemModel ? host.systemModel.keyboardLayout || "us" : "us"
                color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium
                Layout.fillWidth: true
            }
        }
    }
}
