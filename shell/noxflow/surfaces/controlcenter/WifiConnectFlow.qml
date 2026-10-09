import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "../../components" as Components

// WifiConnectFlow — the connect / forget overlay.
//
// Extracted from ControlCentre.qml (1531 lines). The state machine it drives
// (review -> password -> connecting -> saved) lives on the host today; the
// plan moves it into NetworkModel, which is the only component that knows
// about the daemon action these steps perform.

Rectangle {
    // The owning ControlCentre, which owns the connect flow state and
    // the NetworkModel calls that advance it.
    required property var host
    id: wifiConnectionFlow
    visible: host.state.wifiConnectDialogVisible
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
        if (visible && host.state.wifiConnectSecurity !== "open")
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
                onClicked: host.state.cancelWifiConnect()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { text: "Wi‑Fi connection"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true }
                Text { text: host.state.wifiFlowStage === "connecting" ? "Establishing a secure link" : host.state.wifiFlowStage === "failed" ? "Connection needs attention" : "Choose how to connect"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
            }
            Components.IconButton {
                iconText: "✕"
                accessibleName: "Close Wi‑Fi connection flow"
                onClicked: host.state.cancelWifiConnect()
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
                    Text { text: host.state.wifiConnectSsid; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: (host.state.wifiConnectSaved ? "Saved profile" : host.state.wifiConnectSecurity === "open" ? "Open host.network" : "Password protected") + (host.state.wifiConnectSecurity ? " · " + host.state.wifiConnectSecurity : ""); color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: host.state.wifiConnectionState === "connected" ? "Connected" : host.state.wifiConnectionState === "connecting" ? "Connecting…" : "Ready to connect"; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                }
            }
        }

        Text {
            visible: host.state.wifiConnectionMessage !== "" && host.state.wifiConnectionState !== "failed"
            text: host.state.wifiConnectionMessage
            color: Theme.Tokens.tonalPrimary
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Components.TextField {
            id: wifiPasswordField
            visible: host.state.wifiConnectSecurity !== "open" && host.state.wifiFlowStage === "credentials"
            enabled: !host.state.wifiConnectionPending
            label: "Password"
            placeholderText: "Wi‑Fi password"
            password: true
            showPasswordToggle: true
            passwordVisible: host.state.wifiPasswordVisible
            onPasswordVisibilityToggled: function(visible) { host.state.wifiPasswordVisible = visible }
            hasError: host.state.wifiError !== ""
            text: host.state.wifiConnectPassword
            onTextChanged: host.state.wifiConnectPassword = text
            onAccepted: host.state.submitWifiConnect()
            Layout.fillWidth: true
        }
        Text {
            visible: host.state.wifiError !== ""
            text: host.state.wifiError
            color: Theme.Tokens.stateDanger
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }
        Rectangle {
            visible: host.state.wifiConnectionState === "connecting"
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
                Components.TextButton { text: "Cancel"; onClicked: host.state.cancelWifiConnect() }
            }
        }
        RowLayout {
            visible: host.state.wifiConnectionState !== "connecting"
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Components.TextButton { visible: host.state.wifiFlowStage === "credentials"; text: host.state.wifiConnectionState === "failed" ? "Retry" : "Connect"; enabled: !host.state.wifiConnectionPending; onClicked: host.state.submitWifiConnect(false) }
            Components.TextButton { visible: host.state.wifiConnectSaved && (host.state.wifiFlowStage === "review" || host.state.wifiFlowStage === "failed"); text: host.state.wifiFlowStage === "failed" ? "Retry saved" : "Connect saved"; enabled: !host.state.wifiConnectionPending; onClicked: host.state.submitWifiConnect(true) }
            Components.TextButton { visible: host.state.wifiConnectSecurity === "open" && host.state.wifiFlowStage === "review"; text: "Connect"; enabled: !host.state.wifiConnectionPending; onClicked: host.state.submitWifiConnect(false) }
            Components.TextButton { visible: host.state.wifiFlowStage !== "connecting"; text: "Cancel"; onClicked: host.state.cancelWifiConnect() }
        }
        RowLayout {
            visible: host.state.wifiConnectionState !== "connecting" && host.state.wifiConnectSaved
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Components.TextButton { text: "Use another password"; onClicked: host.state.useAnotherWifiPassword() }
            Components.TextButton { text: "Forget"; onClicked: host.state.forgetWifi(host.state.wifiConnectSsid) }
        }
    }
}
