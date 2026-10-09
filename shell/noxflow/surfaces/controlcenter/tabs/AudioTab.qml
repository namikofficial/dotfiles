import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Audio — output device, volume and microphone.
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
    contentHeight: audioContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 1
    interactive: contentHeight > height
    ColumnLayout {
        id: audioContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Text {
            text: "Output · " + (host.audio.available ? host.audio.outputName : "Unavailable")
            color: Theme.Tokens.textSecondary
            font.pixelSize: Theme.Tokens.typographyLabelLarge
            font.family: Theme.Tokens.typographyFontFamily
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingMd
            Components.IconButton {
                iconText: host.audio.outputMuted ? "⊘" : "◉"
                accessibleName: "Toggle mute"
                onClicked: { if (host.noxd.connected) { host.noxd.runAction({ audio_toggle_mute: { target: "output" } }); host.state.markAction("audio", host.audio.outputMuted ? "Unmuting…" : "Muting…"); } }
            }
            Components.Slider {
                Layout.fillWidth: true
                accessibleName: "Output volume"
                value: host.audio.available ? host.audio.outputVolume / host.audio.maxVolume : 0.5
                onMoved: function(value) {
                    if (host.audio.available && host.noxd.connected)
                        host.noxd.runAction({ audio_set_volume: { target: "output", volume: Math.round(value * host.audio.maxVolume) } });
                }
            }
        }
        Repeater {
            model: host.audio.outputs
            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 100
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                radius: Theme.Tokens.radiusSm
                color: modelData.active ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                border.color: modelData.active ? Theme.Tokens.tonalPrimary : "transparent"
                border.width: modelData.active ? 1 : 0
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    Text { text: "◉"; color: modelData.active ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                    Text {
                        text: modelData.description || modelData.name || "Unknown"
                        elide: Text.ElideRight; Layout.fillWidth: true
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                }
                TapHandler {
                    onTapped: {
                        if (host.noxd.connected)
                            host.noxd.runAction({ audio_set_default: { target: "output", selector: modelData.name || modelData.description } })
                    }
                }
            }
        }

        Components.Divider { Layout.fillWidth: true }

        Text {
            text: "Input"
            color: Theme.Tokens.textSecondary
            font.pixelSize: Theme.Tokens.typographyLabelLarge
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingMd
            Components.IconButton {
                iconText: host.audio.inputMuted ? "⊗" : "◌"
                accessibleName: "Toggle mic mute"
                onClicked: { if (host.noxd.connected) host.noxd.runAction({ audio_toggle_mute: { target: "input" } }) }
            }
            Components.Slider {
                Layout.fillWidth: true
                accessibleName: "Input volume"
                value: host.audio.available ? host.audio.inputVolume / host.audio.maxVolume : 0.5
                onMoved: function(value) {
                    if (host.audio.available && host.noxd.connected)
                        host.noxd.runAction({ audio_set_volume: { target: "input", volume: Math.round(value * host.audio.maxVolume) } });
                }
            }
        }
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
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    Text { text: "◌"; color: modelData.active ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                    Text {
                        text: modelData.description || modelData.name || "Unknown"
                        elide: Text.ElideRight; Layout.fillWidth: true
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
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
    }
}
