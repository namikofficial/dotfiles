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
    property bool wifiConnectSaved: false
    property bool wifiPasswordVisible: false
    property string wifiFlowStage: "review"
    property string wifiBackgroundAttemptSsid: ""
    property string wifiBackgroundStatus: ""
    property int wifiAttemptSerial: 0
    property int wifiActiveAttempt: 0
    property bool wifiScanPending: false
    property bool wifiConnectionPending: false
    property string wifiError: ""
    property string wifiConnectionState: "idle"
    property string wifiConnectionMessage: ""
    Timer {
        id: actionStateTimer
        interval: 1800
        repeat: false
        onTriggered: { root.wifiActionState = ""; root.bluetoothActionState = ""; root.audioActionState = ""; }
    }
    Timer {
        id: wifiConnectionTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            if (root.wifiConnectionPending) {
                root.wifiConnectionPending = false;
                root.wifiConnectionState = "failed";
                root.wifiError = "The Wi‑Fi connection timed out. Try again.";
                root.wifiConnectionMessage = root.wifiError;
                root.wifiFlowStage = "failed";
                root.markAction("wifi", "Connection failed");
            }
        }
    }
    Timer {
        id: wifiSuccessTimer
        interval: 900
        repeat: false
        onTriggered: {
            root.wifiConnectDialogVisible = false;
            root.wifiConnectPassword = "";
            root.wifiPasswordVisible = false;
            root.wifiFlowStage = "review";
            root.wifiConnectionState = "idle";
            root.wifiConnectionMessage = "";
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
        root.wifiConnectSaved = networkInfo.saved === true;
        root.wifiConnectPassword = "";
        root.wifiPasswordVisible = false;
        root.wifiError = "";
        root.wifiConnectionState = "idle";
        root.wifiConnectionMessage = "";
        root.wifiConnectionPending = false;
        root.wifiFlowStage = root.wifiConnectSaved || root.wifiConnectSecurity === "open" ? "review" : "credentials";
        root.wifiBackgroundAttemptSsid = "";
        root.wifiBackgroundStatus = "";
        wifiConnectionTimeout.stop();
        wifiSuccessTimer.stop();
        root.wifiConnectDialogVisible = root.wifiConnectSsid !== "";
    }
    function useAnotherWifiPassword() {
        root.wifiFlowStage = "credentials";
        root.wifiConnectionState = "idle";
        root.wifiError = "";
        root.wifiConnectionMessage = "Enter a new password for this saved network.";
        root.wifiPasswordVisible = false;
        Qt.callLater(function() { wifiPasswordField.forceActiveFocus(); });
    }
    function submitWifiConnect(useSavedProfile) {
        if (!root.wifiConnectDialogVisible || root.wifiConnectSsid === "" || !root.noxd.connected) return;
        if (root.wifiConnectionPending) return;
        var savedProfile = useSavedProfile === true && root.wifiConnectSaved;
        if (!savedProfile && root.wifiConnectSecurity !== "open" && root.wifiConnectPassword === "") {
            root.wifiError = "Enter the Wi‑Fi password to continue";
            root.wifiConnectionState = "failed";
            root.wifiFlowStage = "credentials";
            return;
        }
        root.wifiAttemptSerial += 1;
        root.wifiActiveAttempt = root.wifiAttemptSerial;
        var action = savedProfile
            ? { network_connect_saved: { ssid: root.wifiConnectSsid } }
            : { network_connect: { ssid: root.wifiConnectSsid, passphrase: root.wifiConnectPassword } };
        var accepted = root.noxd.runAction(action);
        if (!accepted) {
            root.wifiConnectionState = "failed";
            root.wifiError = "NoxFlow is not connected to the network service. Try again.";
            root.wifiConnectionMessage = root.wifiError;
            root.wifiFlowStage = "failed";
            return;
        }
        root.markAction("wifi", "Connecting to " + root.wifiConnectSsid + "…");
        root.wifiConnectionPending = true;
        root.wifiConnectionState = "connecting";
        root.wifiFlowStage = "connecting";
        root.wifiConnectionMessage = savedProfile ? "Using the saved iwd profile…" : "Connecting securely…";
        root.wifiError = "";
        root.wifiBackgroundAttemptSsid = "";
        root.wifiBackgroundStatus = "";
        wifiConnectionTimeout.restart();
    }
    function cancelWifiConnect() {
        wifiConnectionTimeout.stop();
        wifiSuccessTimer.stop();
        if (root.wifiConnectionPending) {
            root.wifiBackgroundAttemptSsid = root.wifiConnectSsid;
            root.wifiBackgroundStatus = "Connecting to " + root.wifiConnectSsid + "…";
        }
        root.wifiConnectionPending = false;
        root.wifiConnectionState = "idle";
        root.wifiConnectionMessage = "";
        root.wifiError = "";
        root.wifiConnectDialogVisible = false;
        root.wifiFlowStage = "review";
    }
    function forgetWifi(ssid) {
        if (root.noxd.connected) {
            root.noxd.runAction({ network_forget: { ssid: ssid } });
            root.markAction("wifi", "Forgetting " + ssid + "…");
            if (ssid === root.wifiConnectSsid) {
                root.wifiConnectDialogVisible = false;
                root.wifiConnectionPending = false;
            }
        }
    }
    function profileName(value) { return value && typeof value === "object" ? String(value.name || "") : String(value || ""); }
    function profileNames() {
        var result = [];
        var source = power && Array.isArray(power.availableProfiles) ? power.availableProfiles : [];
        for (var i = 0; i < source.length; i++) { var name = profileName(source[i]); if (name !== "") result.push(name); }
        return result.length > 0 ? result : ["power-saver", "balanced", "performance"];
    }
    function wifiList() {
        if (network && network.data && Array.isArray(network.data.available_wifi))
            return network.data.available_wifi;
        return network && Array.isArray(network.availableWifi) ? network.availableWifi : [];
    }

    property bool focusEnabled: false
    property Process dndCheck: Process {
        running: false
        stdout: SplitParser { onRead: function(line) { root.focusEnabled = line.trim() === "true"; } }
    }
    property Process dndSet: Process { running: false }

    anchors.fill: parent
    visible: lifecycle.active

    Rectangle {
        id: wifiConnectionFlow
        visible: root.wifiConnectDialogVisible
        enabled: visible
        z: 20
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
        border.color: Theme.Tokens.glass(Theme.Tokens.tonalPrimary, Theme.Tokens.glassBorderAlpha)
        border.width: 1
        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
        onVisibleChanged: {
            if (visible && root.wifiConnectSecurity !== "open")
                Qt.callLater(function() { wifiPasswordField.forceActiveFocus(); });
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Components.IconButton {
                    iconText: "‹"
                    accessibleName: "Back to Wi‑Fi networks"
                    onClicked: root.cancelWifiConnect()
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: "Wi‑Fi connection"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true }
                    Text { text: root.wifiFlowStage === "connecting" ? "Establishing a secure link" : root.wifiFlowStage === "failed" ? "Connection needs attention" : "Choose how to connect"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                Components.IconButton {
                    iconText: "✕"
                    accessibleName: "Close Wi‑Fi connection flow"
                    onClicked: root.cancelWifiConnect()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: Theme.Tokens.scaled(112)
                radius: Theme.Tokens.radiusLg
                color: Theme.Tokens.tonalPrimaryContainer
                border.color: Theme.Tokens.tonalPrimary
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingLg
                    spacing: Theme.Tokens.spacingMd
                    Rectangle {
                        Layout.preferredWidth: Theme.Tokens.scaled(56)
                        Layout.preferredHeight: Theme.Tokens.scaled(56)
                        radius: Theme.Tokens.radiusPill
                        color: Theme.Tokens.tonalPrimary
                        Text { anchors.centerIn: parent; text: "⌁"; color: Theme.Tokens.tonalOnPrimary; font.pixelSize: Theme.Tokens.iconLg }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.scaled(3)
                        Text { text: root.wifiConnectSsid; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: (root.wifiConnectSaved ? "Saved profile" : root.wifiConnectSecurity === "open" ? "Open network" : "Password protected") + (root.wifiConnectSecurity ? " · " + root.wifiConnectSecurity : ""); color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { text: root.wifiConnectionState === "connected" ? "Connected" : root.wifiConnectionState === "connecting" ? "Connecting…" : "Ready to connect"; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    }
                }
            }

            Text {
                visible: root.wifiConnectionMessage !== "" && root.wifiConnectionState !== "failed"
                text: root.wifiConnectionMessage
                color: Theme.Tokens.tonalPrimary
                font.pixelSize: Theme.Tokens.typographyBodySmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Components.TextField {
                id: wifiPasswordField
                visible: root.wifiConnectSecurity !== "open" && root.wifiFlowStage === "credentials"
                enabled: !root.wifiConnectionPending
                label: "Password"
                placeholderText: "Wi‑Fi password"
                password: true
                showPasswordToggle: true
                passwordVisible: root.wifiPasswordVisible
                onPasswordVisibilityToggled: function(visible) { root.wifiPasswordVisible = visible }
                hasError: root.wifiError !== ""
                text: root.wifiConnectPassword
                onTextChanged: root.wifiConnectPassword = text
                onAccepted: root.submitWifiConnect()
                Layout.fillWidth: true
            }
            Text {
                visible: root.wifiError !== ""
                text: root.wifiError
                color: Theme.Tokens.stateDanger
                font.pixelSize: Theme.Tokens.typographyBodySmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
            Rectangle {
                visible: root.wifiConnectionState === "connecting"
                Layout.fillWidth: true
                height: Theme.Tokens.scaled(54)
                radius: Theme.Tokens.radiusMd
                color: Theme.Tokens.surfaceSurfaceContainer
                border.color: Theme.Tokens.outlineSubtle
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingMd
                    Text { text: "◌"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                    Text { text: "Waiting for iwd and networkd…"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; Layout.fillWidth: true }
                    Components.TextButton { text: "Cancel"; onClicked: root.cancelWifiConnect() }
                }
            }
            RowLayout {
                visible: root.wifiConnectionState !== "connecting"
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Components.TextButton { visible: root.wifiFlowStage === "credentials"; text: root.wifiConnectionState === "failed" ? "Retry" : "Connect"; enabled: !root.wifiConnectionPending; onClicked: root.submitWifiConnect(false) }
                Components.TextButton { visible: root.wifiConnectSaved && (root.wifiFlowStage === "review" || root.wifiFlowStage === "failed"); text: root.wifiFlowStage === "failed" ? "Retry saved" : "Connect saved"; enabled: !root.wifiConnectionPending; onClicked: root.submitWifiConnect(true) }
                Components.TextButton { visible: root.wifiConnectSecurity === "open" && root.wifiFlowStage === "review"; text: "Connect"; enabled: !root.wifiConnectionPending; onClicked: root.submitWifiConnect(false) }
                Components.TextButton { visible: root.wifiFlowStage !== "connecting"; text: "Cancel"; onClicked: root.cancelWifiConnect() }
            }
            RowLayout {
                visible: root.wifiConnectionState !== "connecting" && root.wifiConnectSaved
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Components.TextButton { text: "Use another password"; onClicked: root.useAnotherWifiPassword() }
                Components.TextButton { text: "Forget"; onClicked: root.forgetWifi(root.wifiConnectSsid) }
            }
        }
    }

    Connections {
        target: lifecycle
        function onOpened() {
            var tabs = { network: 2, bluetooth: 3, volume: 1, audio: 1, battery: 0, power: 0, system: 4 };
            if (root.initialSection !== "" && tabs[root.initialSection] !== undefined) root.activeTab = tabs[root.initialSection];
            dndCheck.command = ["dunstctl", "get-paused"]; dndCheck.running = true;
        }
    }

    Connections {
        target: network
        function onAvailableWifiChanged() {
            root.wifiScanPending = false;
        }
        function onConnectedSsidChanged() {
            if (root.wifiConnectionPending && network.connectedSsid === root.wifiConnectSsid && network.connectedSsid !== "") {
                root.wifiConnectionPending = false;
                wifiConnectionTimeout.stop();
                root.wifiError = "";
                root.wifiConnectionState = "connected";
                root.wifiFlowStage = "connected";
                root.wifiConnectionMessage = "Connected successfully.";
                root.markAction("wifi", "Connected");
                wifiSuccessTimer.restart();
            } else if (root.wifiBackgroundAttemptSsid !== "" && network.connectedSsid === root.wifiBackgroundAttemptSsid) {
                root.wifiBackgroundStatus = "Connected to " + root.wifiBackgroundAttemptSsid;
                root.wifiBackgroundAttemptSsid = "";
            }
        }
    }

    Connections {
        target: noxd
        function onEventReceived(event) {
            if (!event || event.provider !== "network" || !event.data) return;
            var action = String(event.data.action || "");
            var ssid = String(event.data.ssid || "");
            if (root.wifiConnectionPending && event.event_type === "action_failed" && action === "connect" && ssid === root.wifiConnectSsid) {
                root.wifiConnectionPending = false;
                wifiConnectionTimeout.stop();
                root.wifiConnectionState = "failed";
                root.wifiError = String(event.data.message || "The Wi‑Fi connection failed. Try again.");
                root.wifiConnectionMessage = root.wifiError;
                root.wifiFlowStage = "failed";
                root.wifiConnectDialogVisible = true;
                root.markAction("wifi", "Connection failed");
            } else if (event.event_type === "action_failed" && action === "connect" && ssid === root.wifiBackgroundAttemptSsid) {
                root.wifiBackgroundStatus = String(event.data.message || "Connection failed. Open the network to retry.");
                root.wifiBackgroundAttemptSsid = "";
            } else if (event.event_type === "action_failed" && action === "refresh") {
                root.wifiScanPending = false;
                root.wifiError = String(event.data.message || "Wi‑Fi scan failed. Try again.");
                root.markAction("wifi", "Scan failed");
            }
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
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
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
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData + " tab"
                            Accessible.description: root.activeTab === index ? "Selected" : ""
                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: root.activeTab === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                font.family: Theme.Tokens.typographyFontFamily
                            }
                            TapHandler { onTapped: { root.activeTab = index; parent.forceActiveFocus(); } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Keys.onReturnPressed: root.activeTab = index
                            Keys.onSpacePressed: root.activeTab = index
                            Keys.onLeftPressed: root.activeTab = Math.max(0, index - 1)
                            Keys.onRightPressed: root.activeTab = Math.min(6, index + 1)
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
                    contentWidth: width
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
                            subtitle: root.wifiActionState || (network.wifiEnabled === false ? "Enable Wi-Fi to connect" : root.wifiList().length + " networks visible")
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
                            Accessible.name: "Do Not Disturb"
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
                                accessibleName: "Screen brightness"
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
                                accessibleName: "Output volume"
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
                    contentWidth: width
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
                                accessibleName: "Output volume"
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
                                accessibleName: "Input volume"
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
                    contentWidth: width
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
                                accessibleName: "Wi-Fi"
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
                        Rectangle {
                            Layout.fillWidth: true
                            visible: network.connectedSsid !== ""
                            height: Theme.Tokens.scaled(58)
                            radius: Theme.Tokens.radiusMd
                            color: Theme.Tokens.tonalPrimaryContainer
                            border.color: Theme.Tokens.tonalPrimary
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.Tokens.spacingMd
                                Text { text: "⌁"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { text: network.connectedSsid; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: "Connected" + (network.signalStrength !== null ? " · " + network.signalStrength + "% signal" : ""); color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                }
                            }
                        }

                        Components.Divider { Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Available Networks"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge; Layout.fillWidth: true }
                            Components.IconButton { iconText: root.wifiScanPending ? "…" : "↻"; accessibleName: "Rescan Wi‑Fi networks"; enabled: !root.wifiScanPending && root.noxd.connected; onClicked: { root.wifiScanPending = true; root.wifiError = ""; root.noxd.runAction({ network_refresh: {} }); root.markAction("wifi", "Scanning for networks…"); } }
                        }
                        Text {
                            visible: root.wifiError !== ""
                            text: root.wifiError
                            color: Theme.Tokens.stateDanger
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            visible: root.wifiBackgroundStatus !== ""
                            Layout.fillWidth: true
                            height: Theme.Tokens.scaled(44)
                            radius: Theme.Tokens.radiusMd
                            color: root.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                            border.color: root.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.Tokens.spacingSm
                                Text { text: root.wifiBackgroundStatus.indexOf("Connected") === 0 ? "✓" : "◌"; color: root.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.stateSuccess : Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconSm }
                                Text { text: root.wifiBackgroundStatus; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
                                Components.TextButton { text: "Dismiss"; onClicked: { root.wifiBackgroundStatus = ""; root.wifiBackgroundAttemptSsid = ""; } }
                            }
                        }
                        Item {
                            visible: root.wifiList().length === 0
                            Layout.fillWidth: true
                            height: Theme.Tokens.scaled(96)
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiScanPending ? "Scanning for nearby networks…" : network.available ? "No networks found. Press Rescan to search." : "Network provider unavailable"
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyBodyMedium
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                width: parent.width
                            }
                        }
                        Repeater {
                            model: root.wifiList()
                            delegate: Rectangle {
                                required property var modelData
                                width: networkContent.width
                                height: Theme.Tokens.scaled(56)
                                radius: Theme.Tokens.radiusMd
                                color: modelData.connected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                                border.color: modelData.connected ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.Tokens.spacingSm
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { text: modelData.ssid || "Hidden SSID"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: modelData.connected === true }
                                        Text { text: (modelData.security === "open" ? "Open network" : "Password required") + (modelData.saved ? " · Saved" : ""); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                    }
                                    Text { text: modelData.strength !== undefined ? Math.round(modelData.strength) + "%" : "—"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                                    Components.TextButton {
                                        id: forgetButton
                                        visible: modelData.saved === true
                                        text: "Forget"
                                        onClicked: root.forgetWifi(String(modelData.ssid || ""))
                                    }
                                }
                                TapHandler { enabled: !forgetButton.pressed; onTapped: root.openWifiConnect(modelData) }
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
                                        accessibleName: (modelData.name || "VPN") + " connection"
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
                    contentWidth: width
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
                                accessibleName: "Bluetooth"
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
                    contentWidth: width
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
                                text: systemModel && systemModel.ready ? Math.round(systemModel.cpuUsage) + "%" : "--"
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
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.memPercent : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel && systemModel.ready ? (systemModel.memUsed / 1024 / 1024).toFixed(1) + "G/" + (systemModel.memTotal / 1024 / 1024).toFixed(1) + "G (" + Math.round(systemModel.memPercent) + "%)" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        // Temperature
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "Temp"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: systemModel && systemModel.ready && systemModel.cpuTemp > 0 ? Math.round(systemModel.cpuTemp) + "°C" : "Unavailable"
                                color: (systemModel && systemModel.cpuTemp > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }

                        // GPU
                        RowLayout {
                            visible: !!systemModel && systemModel.gpuAvailable
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: systemModel && systemModel.gpuName ? systemModel.gpuName : "GPU"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.maximumWidth: 150 }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.gpuUsage : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.gpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text { text: systemModel ? Math.round(systemModel.gpuUsage) + "%" : "--"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        }

                        // Disk
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                            Text { text: "Disk"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.diskPercent : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.diskPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel && systemModel.ready ? (systemModel.diskUsed / 1024 / 1024).toFixed(1) + "G/" + (systemModel.diskTotal / 1024 / 1024).toFixed(1) + "G (" + Math.round(systemModel.diskPercent) + "%)" : "--"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }
                    }
                }

                // ── Input tab (mic, keyboard, touchpad) ──
                Flickable {
                    anchors.fill: parent
                    contentWidth: width
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
                                accessibleName: "Microphone volume"
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
                    contentWidth: width
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
