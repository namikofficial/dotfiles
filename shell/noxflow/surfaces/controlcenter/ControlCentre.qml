// Nox Control — QUIC settings panel.
// Super+Shift+B to open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen

    required property var noxd
    required property var audio
    required property var brightness
    required property var network
    required property var bluetooth
    required property var battery
    required property var power
    required property var hyprland
    required property var systemModel

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    property int activeTab: 0
    property string initialSection: ""
    property bool dndBusy: false
    property string wifiActionState: ""
    property string bluetoothActionState: ""
    property string audioActionState: ""
    property bool wifiConnectDialogVisible: false
    property string wifiConnectSsid: ""
    property string wifiConnectSecurity: ""
    property string wifiConnectPassword: ""
    Timer {
        id: actionStateTimer
        interval: 1800
        repeat: false
        onTriggered: { root.wifiActionState = ""; root.bluetoothActionState = ""; root.audioActionState = ""; }
    }
    property Process wifiConnect: Process {
        running: false
        onExited: {
            if (root.noxd.connected) root.noxd.runAction({ network_refresh: {} });
        }
    }

    // Debounced slider commit
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
    function markAction(kind, message) {
        if (kind === "wifi") root.wifiActionState = message;
        else if (kind === "bluetooth") root.bluetoothActionState = message;
        else root.audioActionState = message;
        actionStateTimer.restart();
    }
    function openWifiConnect(networkInfo) {
        root.wifiConnectSsid = String(networkInfo.ssid || "").trim();
        root.wifiConnectSecurity = String(networkInfo.security || "");
        root.wifiConnectPassword = "";
        root.wifiConnectDialogVisible = root.wifiConnectSsid !== "";
    }
    function submitWifiConnect() {
        if (!root.wifiConnectDialogVisible || root.wifiConnectSsid === "" || !root.noxd.connected) return;
        root.noxd.runAction({ network_connect: { ssid: root.wifiConnectSsid, passphrase: root.wifiConnectPassword } });
        root.markAction("wifi", "Connecting to " + root.wifiConnectSsid + "…");
        root.wifiConnectDialogVisible = false;
        root.wifiConnectPassword = "";
    }
    function forgetWifi(ssid) {
        if (root.noxd.connected) {
            root.noxd.runAction({ network_forget: { ssid: ssid } });
            root.markAction("wifi", "Forgetting " + ssid + "…");
        }
    }
    function profileName(value) { return value && typeof value === "object" ? String(value.name || "") : String(value || ""); }
    function profileNames() {
        var result = [];
        var source = power && Array.isArray(power.availableProfiles) ? power.availableProfiles : [];
        for (var i = 0; i < source.length; i++) { var name = profileName(source[i]); if (name !== "") result.push(name); }
        return result.length > 0 ? result : ["power-saver", "balanced", "performance"];
    }

    property bool focusEnabled: false
    property Process dndCheck: Process {
        running: false
        stdout: SplitParser { onRead: function(line) { root.focusEnabled = line.trim() === "true"; } }
    }
    property Process dndSet: Process { running: false }

    anchors.fill: parent
    visible: lifecycle.active

    Components.PopupContainer {
        id: wifiConnectPopup
        visible: root.wifiConnectDialogVisible
        enabled: visible
        z: 20
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Tokens.spacingXl * 2, Theme.Tokens.scaled(360))
        height: Theme.Tokens.scaled(230)
        scrim: true
        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.Tokens.spacingSm
            Text { text: "Connect to Wi‑Fi"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleMedium }
            Text { text: root.wifiConnectSsid + (root.wifiConnectSecurity ? " · " + root.wifiConnectSecurity : ""); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
            Components.TextField {
                id: wifiPasswordField
                visible: root.wifiConnectSecurity !== "open"
                label: "Password"
                placeholderText: "Wi‑Fi password"
                password: true
                text: root.wifiConnectPassword
                onTextChanged: root.wifiConnectPassword = text
                onAccepted: root.submitWifiConnect()
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Components.TextButton { text: "Cancel"; onClicked: { root.wifiConnectDialogVisible = false; root.wifiConnectPassword = ""; } }
                Components.TextButton { text: "Connect"; onClicked: root.submitWifiConnect() }
            }
        }
    }

    Connections {
        target: lifecycle
        function onOpened() {
            var tabs = { network: 2, bluetooth: 3, volume: 1, audio: 1, battery: 0, power: 0 };
            if (root.initialSection !== "" && tabs[root.initialSection] !== undefined) root.activeTab = tabs[root.initialSection];
            if (root.noxd.connected) root.noxd.runAction({ network_refresh: {} });
            dndCheck.command = ["dunstctl", "get-paused"]; dndCheck.running = true;
        }
    }

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")
    }

    // ── Panel background ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        // MorphSurface owns the geometry transition. Keep the actual surface
        // opaque and stable so the panel never looks disabled during opening.
        scale: 1
        opacity: 1

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
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Tab bar ──
            Flickable {
                id: tabScroller
                Layout.fillWidth: true
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                clip: true
                contentWidth: tabRow.implicitWidth
                interactive: contentWidth > width
                Row {
                    id: tabRow
                    spacing: Theme.Tokens.spacingXs
                    Repeater {
                        model: ["Quick", "Audio", "Net", "BT", "System", "Input", "Power"]
                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            width: tabLabel.implicitWidth + Theme.Tokens.scaled(20)
                            height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                            radius: Theme.Tokens.radiusPill
                            color: root.activeTab === index ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                            border.color: root.activeTab === index ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                            border.width: 1
                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: root.activeTab === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                font.family: Theme.Tokens.typographyFontFamily
                            }
                            TapHandler { onTapped: root.activeTab = index }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
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

                        Components.ControlTile {
                            icon: network.connectivity === "full" || network.connectedSsid !== "" ? "⌁" : "⌁"
                            label: network.displayState
                            subtitle: root.wifiActionState || (network.wifiEnabled === false ? "Enable Wi-Fi to connect" : network.availableWifi.length + " networks visible")
                            active: network.wifiUsable
                            statusColor: network.connectivity === "full" ? Theme.Tokens.stateSuccess : network.connectivity === "limited" ? Theme.Tokens.stateWarning : Theme.Tokens.stateDanger
                            onClicked: root.activeTab = 2
                        }

                        Components.ControlTile {
                            icon: "◈"
                            label: bluetooth.displayState
                            subtitle: root.bluetoothActionState || (bluetooth.devices.length + " paired/seen devices")
                            active: bluetooth.adapterPresent
                            statusColor: bluetooth.powered ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
                            onClicked: root.activeTab = 3
                        }

                        Components.ControlTile {
                            icon: root.focusEnabled ? "⊘" : "◈"
                            label: root.focusEnabled ? "Do Not Disturb (ON)" : "Do Not Disturb"
                            active: true
                            statusColor: root.focusEnabled ? Theme.Tokens.tonalPrimary : Theme.Tokens.textSecondary
                            toggleChecked: root.focusEnabled
                            showToggle: true
                            onToggleChanged: function(value) {
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
                                onMoved: root.queueBrightness(value)
                            }
                            Text {
                                text: Math.round(brightness.available ? brightness.percentage : 50) + "%"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        // Volume
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
                                onMoved: root.queueVolume(value)
                            }
                            Text {
                                text: audio.available ? audio.outputVolumePercent + "% · " + audio.outputName : "Audio unavailable"
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
                                    color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceVariant
                                    border.color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimary : "transparent"
                                    border.width: power.activeProfile === modelData ? 1 : 0
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData === "power-saver" ? "🪫" : modelData === "balanced" ? "🔋" : "⚡"
                                        color: power.activeProfile === modelData ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    }
                                    TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ power_profile_set: { profile: modelData } }) } }
                                }
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }

                        // Power profile cycle
                        RowLayout {
                            Layout.fillWidth: true
                            visible: power.profilesAvailable
                            Text { text: "⚡"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Text {
                                text: "Confirmed profile: " + (power.activeProfile || "Unknown")
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
                                            var profiles = root.profileNames();
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

                        Text {
                            text: "Output · " + (audio.available ? audio.outputName : "Unavailable")
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelLarge
                            font.family: Theme.Tokens.typographyFontFamily
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingMd
                            Components.IconButton {
                                iconText: audio.outputMuted ? "⊘" : "◉"
                                accessibleName: "Toggle mute"
                                onClicked: { if (root.noxd.connected) { root.noxd.runAction({ audio_toggle_mute: { target: "output" } }); root.markAction("audio", audio.outputMuted ? "Unmuting…" : "Muting…"); } }
                            }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: audio.available ? audio.outputVolume / audio.maxVolume : 0.5
                                onMoved: function(value) {
                                    if (audio.available && root.noxd.connected)
                                        root.noxd.runAction({ audio_set_volume: { target: "output", volume: Math.round(value * audio.maxVolume) } });
                                }
                            }
                        }
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
                                        if (root.noxd.connected)
                                            root.noxd.runAction({ audio_set_default: { target: "output", selector: modelData.name || modelData.description } })
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
                                iconText: audio.inputMuted ? "⊗" : "◌"
                                accessibleName: "Toggle mic mute"
                                onClicked: { if (root.noxd.connected) root.noxd.runAction({ audio_toggle_mute: { target: "input" } }) }
                            }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: audio.available ? audio.inputVolume / audio.maxVolume : 0.5
                                onMoved: function(value) {
                                    if (audio.available && root.noxd.connected)
                                        root.noxd.runAction({ audio_set_volume: { target: "input", volume: Math.round(value * audio.maxVolume) } });
                                }
                            }
                        }
                        Repeater {
                            model: audio.inputs
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
                                        if (root.noxd.connected)
                                            root.noxd.runAction({ audio_set_default: { target: "input", selector: modelData.name || modelData.description } })
                                    }
                                }
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
                                enabled: network.available
                                checked: network.wifiEnabled === true
                                onToggled: function(value) {
                                    if (root.noxd.connected) {
                                        root.noxd.runAction({ network_wifi_set_enabled: { enabled: value } });
                                        root.markAction("wifi", value ? "Enabling Wi-Fi…" : "Disabling Wi-Fi…");
                                    }
                                }
                            }
                        }
                        Text { text: network.displayState; color: network.connectivity === "full" ? Theme.Tokens.stateSuccess : network.connectivity === "limited" ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text {
                            visible: network.connectedSsid !== ""
                            text: "Connected to: " + network.connectedSsid
                            color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                        }

                        Components.Divider { Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Available Networks"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge; Layout.fillWidth: true }
                            Components.IconButton { iconText: "↻"; accessibleName: "Rescan Wi‑Fi networks"; onClicked: { if (root.noxd.connected) { root.noxd.runAction({ network_refresh: {} }); root.markAction("wifi", "Scanning for networks…"); } } }
                        }
                        Repeater {
                            model: network.availableWifi
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                radius: Theme.Tokens.radiusSm
                                color: Theme.Tokens.surfaceSurfaceContainer
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.ssid || "Hidden SSID"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Text { text: modelData.strength ? Array(Math.round(modelData.strength / 25) + 1).join("▂") : ""; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Text { text: modelData.ssid === network.connectedSsid ? "Connected" : modelData.saved ? "Saved" : "Available"; color: modelData.ssid === network.connectedSsid ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                    Components.TextButton {
                                        visible: modelData.saved === true
                                        text: "Forget"
                                        onClicked: root.forgetWifi(String(modelData.ssid || ""))
                                    }
                                }
                                TapHandler { onTapped: root.openWifiConnect(modelData) }
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }
                        Text { text: "VPN"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: network.vpn
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                color: Theme.Tokens.surfaceSurfaceContainer
                                radius: Theme.Tokens.radiusSm
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.name || "VPN"; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                                    Components.Toggle {
                                        checked: modelData.active === true
                                        onToggled: function(value) { if (root.noxd.connected) root.noxd.runAction({ network_vpn_set_enabled: { uuid: modelData.uuid || "", enabled: value } }) }
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
                                enabled: bluetooth.adapterPresent
                                checked: bluetooth.powered
                                onToggled: function(value) {
                                    if (root.noxd.connected) {
                                        root.noxd.runAction({ bluetooth_set_powered: { powered: value } });
                                        root.markAction("bluetooth", value ? "Turning Bluetooth on…" : "Turning Bluetooth off…");
                                    }
                                }
                            }
                        }
                        Components.IconButton {
                            iconText: bluetooth.discovering ? "◉" : "◌"
                            accessibleName: "Discover devices"
                            enabled: bluetooth.powered
                            onClicked: { if (root.noxd.connected) root.noxd.runAction({ bluetooth_set_discovering: { discovering: !bluetooth.discovering } }) }
                        }
                        Text {
                            visible: bluetooth.discovering
                            text: "Discovering nearby devices…"
                            color: Theme.Tokens.tonalPrimary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                        }

                        Components.Divider { Layout.fillWidth: true }
                        Text { text: "Devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: bluetooth.devices
                            delegate: Rectangle {
                                required property var modelData
                                width: parent ? parent.width : 100
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                radius: Theme.Tokens.radiusSm
                                color: modelData.connected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                                border.color: modelData.connected ? Theme.Tokens.tonalPrimary : "transparent"
                                border.width: modelData.connected ? 1 : 0
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.Tokens.spacingSm
                                    Text { text: modelData.icon || "◈"; color: modelData.connected ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        Text { text: modelData.name || "Unknown"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                                        Text { text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : ""; color: modelData.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                    }
                                    Rectangle {
                                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip - 8)
                                        implicitWidth: Theme.Tokens.scaled(50)
                                        radius: Theme.Tokens.radiusPill
                                        color: Theme.Tokens.surfaceSurfaceVariant
                                        visible: modelData.connected
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Disconnect"
                                            color: Theme.Tokens.textSecondary
                                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                                        }
                                        TapHandler { onTapped: { if (root.noxd.connected) { root.noxd.runAction({ bluetooth_disconnect: { device_id: modelData.id || modelData.path || "" } }); root.markAction("bluetooth", "Disconnecting…"); } } }
                                    }
                                }
                                TapHandler { onTapped: { if (root.noxd.connected && !modelData.connected && modelData.paired) { root.noxd.runAction({ bluetooth_connect: { device_id: modelData.id || modelData.path || "" } }); root.markAction("bluetooth", "Connecting…"); } } }
                            }
                        }
                    }
                }

                // ── System tab (CPU/RAM/Disk) ──
                Flickable {
                    anchors.fill: parent
                    contentHeight: systemContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 4
                    interactive: contentHeight > height
                    ColumnLayout {
                        id: systemContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingMd

                        Text { text: "System Resources"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }

                        // CPU
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "CPU"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.cpuUsage : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel ? Math.round(systemModel.cpuUsage) + "%" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                                Layout.preferredWidth: 50
                            }
                        }

                        // RAM
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "RAM"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * (systemModel ? systemModel.memoryUsage / 100 : 0)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.memoryUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel ? Math.round(systemModel.memoryUsed / 1024) + "G/" + Math.round(systemModel.memoryTotal / 1024) + "G" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        // Disk
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "Disk"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * (systemModel ? systemModel.diskUsage / 100 : 0)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.diskUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel ? Math.round(systemModel.diskUsed / 1024) + "G/" + Math.round(systemModel.diskTotal / 1024) + "G" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }
                    }
                }

                // ── Input tab (mic, keyboard, touchpad) ──
                Flickable {
                    anchors.fill: parent
                    contentHeight: inputContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 5
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
                                text: audio.inputMuted ? "⊗" : "◌"
                                color: audio.inputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.tonalPrimary
                                font.pixelSize: Theme.Tokens.iconMd
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ audio_toggle_mute: { target: "input" } }) } }
                            }
                            Components.Slider {
                                Layout.fillWidth: true
                                value: audio.available ? audio.inputVolume / audio.maxVolume : 0.5
                                onMoved: function(value) {
                                    if (audio.available && root.noxd.connected)
                                        root.noxd.runAction({ audio_set_volume: { target: "input", volume: Math.round(value * audio.maxVolume) } });
                                }
                            }
                        }

                        // Input devices
                        Text { text: "Input Devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
                        Repeater {
                            model: audio.inputs
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
                                        if (root.noxd.connected)
                                            root.noxd.runAction({ audio_set_default: { target: "input", selector: modelData.name || modelData.description } })
                                    }
                                }
                            }
                        }

                        // Keyboard layout
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "⌨"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Text {
                                text: systemModel ? systemModel.keyboardLayout || "us" : "us"
                                color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // ── Power tab (profiles + battery) ──
                Flickable {
                    anchors.fill: parent
                    contentHeight: powerContent.height + Theme.Tokens.spacingLg
                    visible: root.activeTab === 6
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
                            visible: battery.available
                            Text { text: battery.chargingState === "charging" ? "⚡" : battery.chargingState === "full" ? "🔋" : "🪫"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Rectangle {
                                Layout.fillWidth: true; height: 12; radius: 6
                                color: Theme.Tokens.outlineSubtle
                                border.color: Theme.Tokens.outlineDefault; border.width: 1
                                Rectangle {
                                    width: parent.width * Math.min(1, (battery.percentage || 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: (battery.percentage || 0) > 20 ? Theme.Tokens.stateSuccess : Theme.Tokens.stateDanger
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: Math.round(battery.percentage || 0) + "%"
                                    color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    font.bold: true
                                }
                            }
                        }

                        Components.Divider { Layout.fillWidth: true; visible: power.profilesAvailable }

                        // Power profiles
                        Text {
                            text: "Profile"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge
                            visible: power.profilesAvailable
                        }
                        Repeater {
                            model: root.profileNames()
                            delegate: Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                radius: Theme.Tokens.radiusPill
                                color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceVariant
                                border.color: power.activeProfile === modelData ? Theme.Tokens.tonalPrimary : "transparent"
                                border.width: power.activeProfile === modelData ? 1 : 0
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData === "power-saver" ? "🪫 Power Saver" : modelData === "balanced" ? "🔋 Balanced" : "⚡ Performance"
                                    color: power.activeProfile === modelData ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyBodySmall
                                }
                                TapHandler { onTapped: { if (root.noxd.connected) root.noxd.runAction({ power_profile_set: { profile: modelData } }) } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
