import QtQuick
import QtQuick.Layouts
import Quickshell
import "theme" as Theme
import "components" as Components
import "surfaces/notifications" as NotificationSurfaces
import "surfaces/radialmenu" as RadialMenuSurface
import "surfaces/launcher" as LauncherSurface

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
    required property NotificationModel notifModel
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
            Components.TextButton { text: "Surfaces"; onClicked: root.selectedPage = 1 }
            Components.TextButton { text: "Diagnostics"; onClicked: root.selectedPage = 2 }
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
                    Components.Elevation { level: 1; Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(120); Rectangle { anchors.fill: parent; color: "transparent"; Text { anchors.centerIn: parent; text: "Elevation 1\nLow depth"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleSmall; horizontalAlignment: Text.AlignHCenter } } }
                    Components.Elevation { level: 3; Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(120); Rectangle { anchors.fill: parent; color: "transparent"; Text { anchors.centerIn: parent; text: "Elevation 3\nHigh depth"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleSmall; horizontalAlignment: Text.AlignHCenter } } }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingLg
                    Components.Card { Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(120); Text { text: "Surface / Card\nLayered container"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; wrapMode: Text.Wrap } }
                    Components.PopupContainer { Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(120); Text { text: "Popup container\nOutline + elevation"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; wrapMode: Text.Wrap } }
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
                    spacing: Theme.Tokens.spacingMd
                    Components.Toggle { checked: true }
                    Text { text: "Toggle"; color: Theme.Tokens.textSecondary }
                    Components.Slider { Layout.fillWidth: true; value: 0.65 }
                    Text { text: "Slider"; color: Theme.Tokens.textSecondary }
                    Components.MaterialIcon { icon: "★"; size: "md"; iconColor: Theme.Tokens.tonalPrimary }
                    Text { text: "MaterialIcon"; color: Theme.Tokens.textSecondary }
                    Components.MaterialIcon { icon: "♻"; size: "lg"; iconColor: Theme.Tokens.stateSuccess }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingMd
                    Components.TextField { Layout.fillWidth: true; label: "Search"; placeholderText: "Type to search..."; showClearButton: true }
                    Components.TextField { Layout.fillWidth: true; label: "Password"; placeholderText: "••••••••"; helperText: "Min 8 characters"; hasError: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Components.Divider { vertical: true; Layout.fillHeight: true }
                    Text { text: "Vertical divider"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Components.Divider { vertical: true; Layout.fillHeight: true }
                }
                Text { text: "Keyboard focus, hover, pressed, disabled, contrast-validated, and reduced-motion states are shared by every primitive."; color: Theme.Tokens.textMuted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedPage === 2
            Diagnostics { anchors.fill: parent; client: root.client; hyprland: root.hyprland; audio: root.audio; brightness: root.brightness; battery: root.battery; power: root.power; network: root.network; bluetooth: root.bluetooth; media: root.media }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedPage === 1
            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.Tokens.spacingLg
                Text { text: "Surfaces"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyHeadlineMedium }
                Text { text: "Nox Island (live preview)"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium }
                // Island state triggers
                RowLayout {
                    spacing: Theme.Tokens.spacingMd
                    Components.TextButton { text: "Volume 68%"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.show("volume", "Volume", "◉", 68, 100) } }
                    Components.TextButton { text: "Brightness 42%"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.show("brightness", "Brightness", "☼", 42, 100) } }
                    Components.TextButton { text: "Mic muted"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.show("mic", "Mic muted", "⊗", 0, 1) } }
                    Components.TextButton { text: "Recording"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.showRecording() } }
                    Components.TextButton { text: "Timer 5:00"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.startTimer(300) } }
                    Components.TextButton { text: "Media"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.show("media", "Never Gonna Give You Up", "♫", 50, 100) } }
                    Components.TextButton { text: "Hide"; onClicked: { if (typeof window === "undefined" || !window.noxIslandPreview) return; window.noxIslandPreview.deactivate() } }
                }
                NoxIsland {
                    id: previewIsland
                    noxd: root.client; audio: root.audio; brightness: root.brightness
                    screen: root.screen
                }
                Component.onCompleted: { if (typeof window !== "undefined") window.noxIslandPreview = previewIsland }

                Components.Divider { Layout.fillWidth: true }

                Text { text: "Notification Centre (demo)"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium }
                RowLayout {
                    spacing: Theme.Tokens.spacingMd
                    Components.TextButton { text: "Add System"; onClicked: root.notifModel.addNotification("System", "Update available", "System update 24.04 is ready to install", "◈", "low") }
                    Components.TextButton { text: "Add Chat"; onClicked: root.notifModel.addNotification("Chat", "New message from Alice", "Hey, are you free for lunch?", "◈", "normal") }
                    Components.TextButton { text: "Add Critical"; onClicked: root.notifModel.addNotification("Battery", "Battery critically low", "10% remaining — plug in now", "⚡", "critical", [{id: "dismiss", label: "Dismiss"}]) }
                    Components.TextButton { text: "Dismiss last"; onClicked: { var n = root.notifModel.notifications; if (n.length) root.notifModel.dismissNotification(n[n.length - 1].id) } }
                    Components.TextButton { text: "Clear all"; onClicked: root.notifModel.clearAll() }
                }

                // NotificationCentre in compact preview mode
                NotificationSurfaces.NotificationCentre {
                    id: previewNc
                    noxd: root.client; notifModel: root.notifModel
                    screen: root.screen
                    panelOpen: true
                    openProgress: 1
                }

                Components.Divider { Layout.fillWidth: true }

                Text { text: "Radial Wheel (demo)"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium }
                RowLayout {
                    spacing: Theme.Tokens.spacingMd
                    Components.TextButton { text: "Open wheel"; onClicked: { if (window.radialPreview) window.radialPreview.open() } }
                    Components.TextButton { text: "Close wheel"; onClicked: { if (window.radialPreview) window.radialPreview.close() } }
                }
                RadialMenuSurface.RadialWheel {
                    id: radialPreview
                    noxd: root.client
                    screen: root.screen
                    width: Theme.Tokens.scaled(240)
                    height: Theme.Tokens.scaled(240)
                    openProgress: 1
                    wheelOpen: true
                }
                Component.onCompleted: { if (typeof window !== "undefined") window.radialPreview = radialPreview }

                Components.Divider { Layout.fillWidth: true }

                Text { text: "Universal Launcher (demo)"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium }
                RowLayout {
                    spacing: Theme.Tokens.spacingMd
                    Components.TextButton { text: "Open launcher"; onClicked: { if (window.launcherPreview) window.launcherPreview.open() } }
                    Components.TextButton { text: "Close launcher"; onClicked: { if (window.launcherPreview) window.launcherPreview.close() } }
                }
                LauncherSurface.Launcher {
                    id: launcherPreview
                    noxd: root.client; hyprland: root.hyprland
                    screen: root.screen
                    launcherOpen: true
                }
                Component.onCompleted: { if (typeof window !== "undefined") window.launcherPreview = launcherPreview }
            }
        }
    }
}
