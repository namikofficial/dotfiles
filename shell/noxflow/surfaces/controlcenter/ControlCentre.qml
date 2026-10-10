// Nox Control — QUIC settings panel.
// Super+Shift+B to open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components
import "../../ModelUtils.js" as Utils
import "tabs" as Tabs

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
    // Optional: the DND tile degrades gracefully when a caller does not supply
    // one, but every current caller does.
    property var notificationModel: null

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    // ── View state ──
    //
    // The Wi-Fi connect flow, the Bluetooth pairing hand-off, the slider commit
    // debounce and the DND read-out live in ControlCentreState. The host passes
    // the models it already holds, so there is still exactly one set of live
    // models; this only gives the state machine a name of its own.
    ControlCentreState {
        id: viewState
        screen: root.screen
        noxd: root.noxd
        network: root.network
        bluetooth: root.bluetooth
        audio: root.audio
        power: root.power
        notificationModel: root.notificationModel
    }
    readonly property var state: viewState



    anchors.fill: parent
    visible: lifecycle.active

    WifiConnectFlow { host: root }
    Connections {
        target: lifecycle
        function onOpened() {
            // The sheet is intentionally single-surface now. Keep the old
            // activeTab field as a compatibility seam for callers, but route
            // every deep link into the unified content and remember which
            // section should be expanded first.
            var sectionTabs = { network: 2, volume: 1, audio: 1, system: 4, input: 5, power: 6, battery: 0 };
            state.activeTab = sectionTabs[state.initialSection] !== undefined ? sectionTabs[state.initialSection] : 0;
            state.expandedSection = state.initialSection === "bluetooth" ? "bluetooth" : "";
        }
    }

    Connections {
        target: network
        function onAvailableWifiChanged() {
            state.wifiScanPending = false;
        }
        // The connect flow resolves itself inside NetworkModel now, so this
        // connection only carries the model's transient status into the panel.
        function onWifiStatus(kind, message) {
            state.markAction(kind, message);
        }
    }

    Connections {
        target: bluetooth
        function onDiscoveringChanged() {
            if (bluetooth.discovering) bluetooth.pairingError = "";
        }
        function onPoweredChanged() {
            if (bluetooth.powered) bluetooth.pairingError = "";
        }
    }

    Connections {
        target: noxd
        function onEventReceived(event) {
            if (!event || !event.data) return;
            if (event.provider === "bluetooth" && event.event_type === "action_failed") {
                state.bluetoothActionState = "";
                root.bluetooth.pairingError = String(event.data.message || "Bluetooth action failed. Try again.");
                state.markAction("bluetooth", "Bluetooth action failed");
                return;
            }
            if (event.provider !== "network") return;
            var action = String(event.data.action || "");
            var ssid = String(event.data.ssid || "");
            if (event.event_type === "action_failed" && action === "connect") {
                network.onConnectFailed(ssid, event.data.message);
            } else if (event.event_type === "action_failed" && action === "refresh") {
                state.wifiScanPending = false;
                state.wifiError = String(event.data.message || "Wi‑Fi scan failed. Try again.");
                state.markAction("wifi", "Scan failed");
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
                    font.family: Theme.Tokens.typographyDisplayFamily
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

            ControlTabBar { host: root }

            // ── Tab content ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Tabs.QuickTab { host: root }

                Tabs.AudioTab { host: root }

                Tabs.NetworkTab { host: root }

                Tabs.BluetoothTab { host: root }

                Tabs.SystemTab { host: root }

                Tabs.InputTab { host: root }

                Tabs.PowerTab { host: root }
            }
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
