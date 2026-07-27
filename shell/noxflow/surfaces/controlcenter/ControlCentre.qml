// Nox Control — QUIC settings panel.
// Stolen from: DankMaterialShell ControlCenter + end-4 sidebarRight.
// Opened with Super + A.
// Connects to existing noxd providers via NoxdClient and QML models.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var audio
    required property var brightness
    required property var network
    required property var bluetooth
    required property var battery
    required property var power
    required property var hyprland

    /// Current animation phase for morphing panel
    property real openProgress: 0
    property bool panelOpen: false
    property int activeTab: 0 // 0: quick, 1: audio, 2: network, 3: bluetooth
    property bool focusEnabled: false
    property bool dndBusy: false

    // ── Debounced slider commit ──
    property real pendingBrightness: -1
    property real pendingVolume: -1
    Timer {
        id: sliderCommitTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root.pendingBrightness >= 0 && root.noxd.connected) {
                root.noxd.runAction({ brightness_set: { percentage: Math.round(root.pendingBrightness * 100) } });
                root.pendingBrightness = -1;
            }
            if (root.pendingVolume >= 0 && root.noxd.connected) {
                root.noxd.runAction({ audio_set_volume: { target: "output", volume: Math.round(root.pendingVolume * (audio.maxVolume || 100)) } });
                root.pendingVolume = -1;
            }
        }
    }
    function queueBrightness(v) { root.pendingBrightness = v; sliderCommitTimer.restart(); }
    function queueVolume(v) { root.pendingVolume = v; sliderCommitTimer.restart(); }

    // ── DND toggle via dunstctl ──
    property Process dndCheck: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                root.focusEnabled = line.trim() === "true";
            }
        }
    }
    property Process dndSet: Process {
        running: false
    }

    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    margins.top: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingSm)
    margins.bottom: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    margins.right: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    implicitWidth: Theme.Tokens.scaled(380)
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: panelOpen

    Behavior on width {
        NumberAnimation { duration: Theme.Tokens.duration(250); easing.type: Easing.OutCubic }
    }

    // ── Panel background with morphing entrance ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        opacity: root.openProgress
        scale: 0.85 + 0.15 * root.openProgress
        Behavior on scale {
            NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.Tokens.duration(150) }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Control Centre"
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyTitleLarge
                    font.bold: true
                    Layout.fillWidth: true
                }
                Components.IconButton {
                    iconText: "✕"
                    accessibleName: "Close control centre"
                    onClicked: root.close()
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Tab bar ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingXs
                Repeater {
                    model: ["Quick", "Audio", "Network", "Bluetooth"]
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                        radius: Theme.Tokens.radiusPill
                        color: root.activeTab === index ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: root.activeTab === index ? Theme.Tokens.tonalPrimary : "transparent"
                        border.width: root.activeTab === index ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.activeTab === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelMedium
                            font.family: Theme.Tokens.typographyFontFamily
                        }
                        TapHandler {
                            onTapped: root.activeTab = index
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Tab content ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Quick tab
                Flickable {
                    anchors.fill: parent
                    contentHeight: quickContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 0
                    interactive: contentHeight > height
                    ColumnLayout {
                        id: quickContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingMd

                        // Network tile
                        Components.ControlTile {
                            icon: network.connectivity === "full" || network.connectedSsid !== "" ? "⌁" : "⌁"
                            label: network.connectedSsid || (network.connectivity === "full" ? "Connected" : network.connectivity === "limited" ? "Limited" : "Offline")
                            subtitle: network.connectivity === "full" ? network.connectedSsid || "Wi-Fi" : ""
                            active: network.available
                            statusColor: network.connectivity === "full" ? Theme.Tokens.stateSuccess : network.connectivity === "limited" ? Theme.Tokens.stateWarning : Theme.Tokens.stateDanger
                            onClicked: root.activeTab = 2
                        }

                        // Bluetooth tile
                        Components.ControlTile {
                            icon: "◈"
                            label: bluetooth.powered ? "Bluetooth" : "Bluetooth Off"
                            subtitle: bluetooth.powered ? bluetooth.devices.filter(d => d.connected).map(d => d.name).join(", ") || "No devices" : ""
                            active: bluetooth.adapterPresent
                            statusColor: bluetooth.powered ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
                            onClicked: root.activeTab = 3
                        }

                        // DND tile
                        Components.ControlTile {
                            icon: root.focusEnabled ? "⊘" : "◈"
                            label: root.focusEnabled ? "Do Not Disturb (ON)" : "Do Not Disturb"
                            active: true
                            statusColor: root.focusEnabled ? Theme.Tokens.tonalPrimary : Theme.Tokens.textSecondary
                            toggleChecked: root.focusEnabled
                            showToggle: true
                            onToggleChanged: {
                                if (root.dndBusy) return;
                                root.dndBusy = true;
                                root.dndSet.command = ["dunstctl", value ? "set-paused" : "set-paused", value ? "true" : "false"];
                                root.dndSet.running = true;
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }

                        // Brightness
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingMd
                            Text { text: "☼"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: brightness.available ? brightness.percentage / 100 : 0.5
                                onValueChanged: root.queueBrightness(value)
                            }
                            Text {
                                text: Math.round(brightness.available ? brightness.percentage : 50) + "%"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        // Volume (master output)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingMd
                            Text {
                                text: audio.outputMuted ? "⊘" : "◉"
                                color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.tonalPrimary
                                font.pixelSize: Theme.Tokens.iconMd
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ audio_toggle_mute: { target: "output" } }) } }
                            }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: audio.available ? audio.outputVolume / audio.maxVolume : 0.5
                                onValueChanged: root.queueVolume(value)
                            }
                            Text {
                                text: audio.available ? audio.outputVolume + "%" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }

                        // Battery mode drawer
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingMd
                            visible: power.profilesAvailable
                            Text { text: "🔋"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Text {
                                text: "Mode: " + (power.activeProfile || "balanced")
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
                                    color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceVariant
                                    border.color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimary : "transparent"
                                    border.width: power.activeProfile === modelData ? 1 : 0
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData === "power-saver" ? "🪫" : modelData === "balanced" ? "🔋" : "⚡"
                                        color: power.activeProfile === modelData ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    }
                                    TapHandler {
                                        onTapped: { if (root.noxd.connected) root.noxd.runAction({ power_profile_set: { profile: modelData } }) }
                                    }
                                }
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }

                        // Power profile (cycle)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: power.profilesAvailable
                            Text { text: "⚡"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Text {
                                text: "Profile: " + (power.activeProfile || "balanced")
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
                                        if (root.noxd.connected) {
                                            var profiles = power.availableProfiles;
                                            var idx = profiles.indexOf(power.activeProfile);
                                            var next = profiles[(idx + 1) % profiles.length];
                                            root.noxd.runAction({ power_profile_set: { profile: next } });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Audio tab
                Flickable {
                    anchors.fill: parent
                    contentHeight: audioContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 1
                    interactive: contentHeight > height
                    ColumnLayout {
                        id: audioContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingMd

                        // Output volume
                        Text { text: "Output"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge; font.family: Theme.Tokens.typographyFontFamily }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingMd
                            Components.IconButton {
                                iconText: audio.outputMuted ? "⊘" : "◉"
                                accessibleName: "Toggle mute"
                                onClicked: { if (root.noxd.connected) root.noxd.runAction({ audio_toggle_mute: { target: "output" } }) }
                            }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: audio.available ? audio.outputVolume / audio.maxVolume : 0.5
                                onValueChanged: {
                                    if (audio.available && root.noxd.connected) root.noxd.runAction({ audio_set_volume: { target: "output", volume: Math.round(value * audio.maxVolume) } });
                                }
                            }
                        }
                        // Output devices
                        Repeater {
                            model: audio.outputs
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
                                    Text { text: "◉"; color: modelData.active ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                                    Text { text: modelData.description || modelData.name || "Unknown"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                }
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ audio_set_default: { target: "output", selector: modelData.name || modelData.description } }) } }
                            }
                        }
                        Components.Divider { Layout.fillWidth: true }
                        // Input volume
                        Text { text: "Input"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Components.IconButton { iconText: audio.inputMuted ? "⊗" : "◌"; accessibleName: "Toggle mic mute"; onClicked: { if (root.noxd.connected) root.noxd.runAction({ audio_toggle_mute: { target: "input" } }) } }
                            Components.Slider { Layout.fillWidth: true; value: audio.available ? audio.inputVolume / audio.maxVolume : 0.5 }
                        }
                        Repeater {
                            model: audio.inputs
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusSm
                                color: modelData.active ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                                border.color: modelData.active ? Theme.Tokens.tonalPrimary : "transparent"
                                border.width: modelData.active ? 1 : 0
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: "◌"; color: modelData.active ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                                    Text { text: modelData.description || modelData.name || "Unknown"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                }
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ audio_set_default: { target: "input", selector: modelData.name || modelData.description } }) } }
                            }
                        }
                    }
                }

                // Network tab
                Flickable {
                    anchors.fill: parent
                    contentHeight: networkContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 2
                    interactive: contentHeight > height
                    ColumnLayout {
                        id: networkContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingMd

                        Text { text: "Network"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Wi-Fi"; color: Theme.Tokens.textPrimary }
                            Item { Layout.fillWidth: true }
                            Components.Toggle {
                                checked: network.networkingEnabled
                                onToggled: { if (root.noxd.connected) root.noxd.runAction({ network_wifi_set_enabled: { enabled: value } }) }
                            }
                        }
                        Text { text: "Status: " + network.connectivity; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { visible: network.connectedSsid !== ""; text: "Connected to: " + network.connectedSsid; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }

                        Components.Divider { Layout.fillWidth: true }
                        Text { text: "Available Networks"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: network.availableWifi
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusSm
                                color: Theme.Tokens.surfaceSurfaceContainer
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.ssid || "Hidden SSID"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Text { text: modelData.strength ? Array(Math.round(modelData.strength / 25) + 1).join("▂") : ""; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Text { text: modelData.active ? "Connected" : ""; color: Theme.Tokens.stateSuccess; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                }
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ network_connect_saved: { uuid: modelData.uuid || "" } }) } }
                            }
                        }
                        Components.Divider { Layout.fillWidth: true }
                        Text { text: "VPN"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: network.vpn
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100; height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                color: Theme.Tokens.surfaceSurfaceContainer; radius: Theme.Tokens.radiusSm
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.name || "VPN"; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Components.Toggle {
                                        checked: modelData.active === true
                                        onToggled: { if (root.noxd.connected) root.noxd.runAction({ network_vpn_set_enabled: { uuid: modelData.uuid || "", enabled: value } }) }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bluetooth tab
                Flickable {
                    anchors.fill: parent
                    contentHeight: bluetoothContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 3
                    interactive: contentHeight > height
                    ColumnLayout {
                        id: bluetoothContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingMd

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Bluetooth"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                            Item { Layout.fillWidth: true }
                            Components.Toggle {
                                checked: bluetooth.powered
                                onToggled: { if (root.noxd.connected) root.noxd.runAction({ bluetooth_set_powered: { powered: value } }) }
                            }
                        }
                        Components.IconButton {
                            iconText: bluetooth.discovering ? "◉" : "◌"
                            accessibleName: "Discover devices"
                            enabled: bluetooth.powered
                            onClicked: { if (root.noxd.connected) root.noxd.runAction({ bluetooth_set_discovering: { discovering: !bluetooth.discovering } }) }
                        }
                        Text { visible: bluetooth.discovering; text: "Discovering..."; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }

                        Components.Divider { Layout.fillWidth: true }
                        Text { text: "Devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: bluetooth.devices
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusSm
                                color: modelData.connected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                                border.color: modelData.connected ? Theme.Tokens.tonalPrimary : "transparent"
                                border.width: modelData.connected ? 1 : 0
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.icon || "◈"; color: modelData.connected ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        Text { text: modelData.name || "Unknown"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                                        Text { text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : ""; color: modelData.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                    }
                                    Rectangle {
                                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip - 8); implicitWidth: Theme.Tokens.scaled(50)
                                        radius: Theme.Tokens.radiusPill; color: Theme.Tokens.surfaceSurfaceVariant
                                        visible: modelData.connected
                                        Text { anchors.centerIn: parent; text: "Disconnect"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                        TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ bluetooth_disconnect: { device_id: modelData.id || modelData.path || "" } }) } }
                                    }
                                }
                                TapHandler { onTapped: { if (root.noxd.connected && !modelData.connected) root.noxd.runAction({ bluetooth_connect: { device_id: modelData.id || modelData.path || "" } }) } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function open() {
        panelOpen = true;
        openProgress = 1;
        forceActiveFocus();
        // Refresh DND state
        dndCheck.command = ["dunstctl", "get-paused"];
        dndCheck.running = true;
    }

    function close() {
        closeAnim.start();
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "openProgress"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
        onFinished: root.panelOpen = false
    }

    function toggle() {
        if (panelOpen) close(); else open();
    }
}
