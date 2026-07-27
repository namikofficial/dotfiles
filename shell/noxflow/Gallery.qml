import QtQuick
import QtQuick.Layouts
import Quickshell
import "theme" as Theme
import "components" as Components

PanelWindow {
    id: root
    required property NoxdClient client
    required property HyprlandModel hyprland
    required property AudioModel audio
    required property BrightnessModel brightness
    required property BatteryModel battery
    required property PowerModel power
    required property NetworkModel network
    required property BluetoothModel bluetooth
    required property MediaModel media
    property int selectedPage: 0
    property bool reducedMotion: false
    property string density: "comfortable"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    focusable: true
    color: Theme.Tokens.tonalBackground
    Component.onCompleted: { Theme.Tokens.reducedMotion = root.reducedMotion; Theme.Tokens.activeDensity = root.density }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.Tokens.scaled(Theme.Tokens.spacingXl)
        spacing: Theme.Tokens.scaled(Theme.Tokens.spacingLg)
        RowLayout {
            Layout.fillWidth: true
            Text { text: "NoxFlow Material gallery"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyDisplayMedium; font.family: Theme.Tokens.typographyFontFamily; Layout.fillWidth: true }
            Components.StatusChip { text: root.density; status: "success" }
            Components.Toggle { checked: root.reducedMotion; onToggled: { root.reducedMotion = value; Theme.Tokens.reducedMotion = value } }
            Text { text: "Reduced motion"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelMedium }
        }
        RowLayout {
            Layout.fillWidth: true
            Components.TextButton { text: "Components"; onClicked: root.selectedPage = 0 }
            Components.TextButton { text: "Diagnostics"; onClicked: root.selectedPage = 1 }
            Components.TextButton { text: "Compact"; onClicked: { root.density = "compact"; Theme.Tokens.activeDensity = root.density } }
            Components.TextButton { text: "Comfortable"; onClicked: { root.density = "comfortable"; Theme.Tokens.activeDensity = root.density } }
            Components.TextButton { text: "Spacious"; onClicked: { root.density = "spacious"; Theme.Tokens.activeDensity = root.density } }
            Item { Layout.fillWidth: true }
            Components.TextButton { text: "Close"; onClicked: root.visible = false }
        }
        Components.Divider { Layout.fillWidth: true }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedPage === 0
            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.Tokens.spacingLg
                Text { text: "Tokens and primitives"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyHeadlineMedium }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingLg
                    Components.Card { Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(160); Text { text: "Surface / Card\nLayered Material container"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; wrapMode: Text.Wrap } }
                    Components.PopupContainer { Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(160); Text { text: "Popup container\nOutline and elevation"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; wrapMode: Text.Wrap } }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingMd
                    Item {
                        implicitWidth: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                        implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                        Components.IconButton { id: sampleIcon; anchors.fill: parent; iconText: "◆"; accessibleName: "Favourite" }
                        Components.FocusRing { targetItem: sampleIcon }
                        Components.Tooltip { target: sampleIcon; text: "Keyboard-focusable icon button" }
                    }
                    Components.TextButton { text: "Text button" }
                    Components.StatusChip { text: "Online"; status: "success" }
                    Components.StatusChip { text: "Attention"; status: "warning" }
                    Components.StatusChip { text: "Offline"; status: "danger" }
                    Components.LoadingIndicator {}
                }
                RowLayout {
                    Layout.fillWidth: true
                    Components.Toggle { checked: true }
                    Text { text: "Toggle"; color: Theme.Tokens.textSecondary }
                    Components.Slider { Layout.fillWidth: true; value: 0.65 }
                    Text { text: "Slider"; color: Theme.Tokens.textSecondary }
                }
                Text { text: "Keyboard focus, hover, pressed, disabled, contrast-validated, and reduced-motion states are shared by every primitive."; color: Theme.Tokens.textMuted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedPage === 1
            Diagnostics { anchors.fill: parent; client: root.client; hyprland: root.hyprland; audio: root.audio; brightness: root.brightness; battery: root.battery; power: root.power; network: root.network; bluetooth: root.bluetooth; media: root.media }
        }
    }
}
