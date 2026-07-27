// Settings Panel — theme profile switching, appearance controls.
// Part of Phase 4.1: Theme profiles & AI integration.
// Toggle with Super+I or from Dashboard quick actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd

    // ── State ──
    property bool panelOpen: false
    property real openProgress: 0

    // ── Window ──
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: panelOpen

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.6)
        opacity: root.openProgress
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(200) } }
        TapHandler { onTapped: root.close() }
    }

    // ── Settings panel ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.7, Theme.Tokens.scaled(520))
        height: Math.min(parent.height * 0.75, Theme.Tokens.scaled(500))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        scale: 0.85 + 0.15 * root.openProgress
        opacity: root.openProgress

        Behavior on scale { NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(150) } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingXl
            spacing: Theme.Tokens.spacingLg

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Settings"
                    color: Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyHeadlineMedium
                    font.family: Theme.Tokens.typographyFontFamily
                    font.bold: true
                    Layout.fillWidth: true
                }
                Components.IconButton {
                    iconText: "✕"
                    accessibleName: "Close settings"
                    onClicked: root.close()
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Scrollable content ──
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: contentColumn.height
                clip: true
                interactive: true

                ColumnLayout {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.Tokens.spacingLg

                    // ── Theme Profile ──
                    Text {
                        text: "Theme Profile"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.family: Theme.Tokens.typographyFontFamily
                        font.bold: true
                    }

                    Text {
                        text: "Switch between colour palettes"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                        font.family: Theme.Tokens.typographyFontFamily
                        visible: true
                    }

                    Repeater {
                        model: ["material-expressive", "material-focus", "material-ambient", "material-performance", "material-oled"]

                        delegate: Rectangle {
                            required property string modelData
                            required property int index

                            readonly property bool isActive: Theme.Tokens.currentProfile === modelData

                            Layout.fillWidth: true
                            height: Theme.Tokens.scaled(48)
                            radius: Theme.Tokens.radiusMd
                            color: isActive ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                            border.color: isActive ? Theme.Tokens.tonalPrimary : "transparent"
                            border.width: isActive ? 1 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.Tokens.spacingLg
                                spacing: Theme.Tokens.spacingMd

                                // Colour swatches
                                Row {
                                    spacing: 3
                                    Layout.alignment: Qt.AlignVCenter
                                    Repeater {
                                        model: [
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.primary,
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.secondary,
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.tertiary,
                                            Theme.ThemeProfiles.getProfile(modelData).surfaces.surface,
                                        ]
                                        delegate: Rectangle {
                                            width: 12; height: 12; radius: 3
                                            color: modelData
                                            border.color: Theme.Tokens.outlineSubtle
                                            border.width: 1
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: {
                                            var labels = {
                                                "material-expressive": "Expressive",
                                                "material-focus": "Focus",
                                                "material-ambient": "Ambient",
                                                "material-performance": "Performance",
                                                "material-oled": "OLED Black",
                                            };
                                            return labels[modelData] || modelData;
                                        }
                                        color: isActive ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary
                                        font.pixelSize: Theme.Tokens.typographyBodyMedium
                                        font.family: Theme.Tokens.typographyFontFamily
                                        font.bold: isActive
                                    }
                                    Text {
                                        text: {
                                            var desc = {
                                                "material-expressive": "Vibrant default palette",
                                                "material-focus": "High contrast, max readability",
                                                "material-ambient": "Soft muted tones",
                                                "material-performance": "Flat, GPU-friendly",
                                                "material-oled": "True black background",
                                            };
                                            return desc[modelData] || "";
                                        }
                                        color: isActive ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                        font.family: Theme.Tokens.typographyFontFamily
                                        visible: text !== ""
                                    }
                                }

                                Text {
                                    text: isActive ? "✓" : ""
                                    color: Theme.Tokens.tonalPrimary
                                    font.pixelSize: Theme.Tokens.iconSm
                                    font.bold: true
                                    visible: isActive
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    Theme.Tokens.applyProfile(modelData);
                                    if (root.noxd && root.noxd.connected) {
                                        root.noxd.setSetting("appearance.profile", modelData);
                                    }
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    Components.Divider { Layout.fillWidth: true }

                    // ── Appearance controls ──
                    Text {
                        text: "Appearance"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.bold: true
                    }

                    // Density
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingMd

                        Text {
                            text: "Density"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: ["compact", "comfortable", "spacious"]
                            delegate: Components.TextButton {
                                required property string modelData
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                Layout.preferredWidth: Theme.Tokens.scaled(80)
                                onClicked: {
                                    Theme.Tokens.activeDensity = modelData;
                                    if (root.noxd && root.noxd.connected) {
                                        root.noxd.setSetting("appearance.density", modelData);
                                    }
                                }
                            }
                        }
                    }

                    // Reduced motion
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingMd

                        Text {
                            text: "Reduced motion"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                            Layout.fillWidth: true
                        }

                        Components.Toggle {
                            checked: Theme.Tokens.reducedMotion
                            onToggled: {
                                Theme.Tokens.reducedMotion = value;
                                if (root.noxd && root.noxd.connected) {
                                    root.noxd.setSetting("shell.reduced_motion", value);
                                }
                            }
                        }
                    }

                    // Corner radius
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingMd

                        Text {
                            text: "Corner radius"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                        }

                        Text {
                            text: Theme.Tokens.appearanceRadius + "px"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            Layout.preferredWidth: Theme.Tokens.scaled(40)
                        }

                        // Quick radius presets
                        Repeater {
                            model: [4, 8, 14, 20, 28]
                            delegate: Components.TextButton {
                                required property int modelData
                                text: modelData + "px"
                                Layout.preferredWidth: Theme.Tokens.scaled(56)
                                onClicked: {
                                    Theme.Tokens.radiusNone = 0;
                                    Theme.Tokens.radiusXs = 4;
                                    Theme.Tokens.radiusSm = 8;
                                    Theme.Tokens.radiusMd = modelData;
                                    Theme.Tokens.radiusLg = Math.min(modelData + 4, 28);
                                    Theme.Tokens.radiusXl = Math.min(modelData + 8, 36);
                                    if (root.noxd && root.noxd.connected) {
                                        root.noxd.setSetting("appearance.radius", modelData);
                                    }
                                }
                            }
                        }
                    }

                    Components.Divider { Layout.fillWidth: true }

                    // ── System actions ──
                    Text {
                        text: "System"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.bold: true
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingSm

                        Components.TextButton { text: "Reload Shell"; onClicked: { Quickshell.exec("systemctl --user reload noxflow-shell"); root.close() } }
                        Components.TextButton { text: "Restart Daemon"; onClicked: { Quickshell.exec("systemctl --user restart noxd"); root.close() } }
                        Components.TextButton { text: "Gallery"; onClicked: { Quickshell.exec("systemctl --user start noxflow-gallery"); root.close() } }
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
