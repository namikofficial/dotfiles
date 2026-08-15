// WallpaperPanel — right-side wallpaper/theme picker (SUPER+W).
// Indexed grid of wallpapers from WALLPAPER_DIRS with async thumbnails.
// Apply delegates to set-wallpaper.sh (hyprpaper + matugen); theme pass
// delegates to theme-pass.sh. No fake state: scan/apply errors surface.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen
    required property var noxd
    required property var wallModel

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    implicitWidth: Theme.Tokens.scaled(480)
    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            if (root.wallModel.walls.length === 0) root.wallModel.scan();
            root.wallModel.readCurrent();
        }
    }

    FocusScope {
        id: focusRoot; focus: lifecycle.interactive; anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")

        Rectangle {
            anchors.fill: parent; radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
            border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
            opacity: root.openProgress; scale: 0.9 + 0.1 * root.openProgress
            transformOrigin: Item.TopRight

            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingMd

                // Header
                RowLayout { Layout.fillWidth: true
                    Text { text: "Wallpaper & Theme"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true; Layout.fillWidth: true }
                    Components.IconButton { iconText: "\uF021"; accessibleName: "Rescan wallpapers"; onClicked: wallModel.scan() }
                    Components.IconButton { iconText: "\uF00D"; accessibleName: "Close"; onClicked: lifecycle.requestClose("closeButton") }
                }

                // Current wallpaper label
                Text { text: root.currentLabel(); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall
                    elide: Text.ElideRight; Layout.fillWidth: true; visible: wallModel.current !== "" }

                // Wallpaper grid
                GridView {
                    id: grid
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    cellWidth: Theme.Tokens.scaled(150)
                    cellHeight: Theme.Tokens.scaled(104)
                    model: wallModel.walls
                    boundsBehavior: Flickable.StopAtBounds
                    focus: lifecycle.interactive

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: grid.cellWidth - Theme.Tokens.spacingSm
                        height: grid.cellHeight - Theme.Tokens.spacingSm
                        radius: Theme.Tokens.radiusMd
                        clip: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Apply wallpaper " + modelData.name
                            color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, Theme.Tokens.glassCardAlpha)
                            border.color: root.isCurrent(modelData.path) ? Theme.Tokens.tonalPrimary
                            : grid.currentIndex === index ? Theme.Tokens.outlineFocus : "transparent"
                        border.width: root.isCurrent(modelData.path) ? 2 : (grid.currentIndex === index ? 2 : 0)

                        // Async thumbnail
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: "file://" + modelData.path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: false
                            visible: thumb.status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            visible: thumb.status !== Image.Ready
                            Text { anchors.centerIn: parent; text: "\uF03E"; color: Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconMd }
                        }

                        // Name overlay
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            height: Theme.Tokens.scaled(22)
                            color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.86)
                            Text { anchors.fill: parent; anchors.leftMargin: Theme.Tokens.spacingXs; verticalAlignment: Text.AlignVCenter
                                text: modelData.name; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyLabelSmall
                                elide: Text.ElideRight }
                        }

                        TapHandler { onTapped: { grid.currentIndex = index; wallModel.apply(modelData.path); } }
                        HoverHandler { onHoveredChanged: { if (hovered) grid.currentIndex = index; } cursorShape: Qt.PointingHandCursor }
                    }

                    // Keyboard
                    Keys.onUpPressed: grid.currentIndex = Math.max(0, grid.currentIndex - Math.floor(grid.width / grid.cellWidth))
                    Keys.onDownPressed: grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + Math.floor(grid.width / grid.cellWidth))
                    Keys.onLeftPressed: grid.currentIndex = Math.max(0, grid.currentIndex - 1)
                    Keys.onRightPressed: grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + 1)
                    Keys.onReturnPressed: { if (grid.currentIndex >= 0 && grid.currentIndex < wallModel.walls.length) wallModel.apply(wallModel.walls[grid.currentIndex].path); }

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }

                // Empty / error state
                Text { text: wallModel.error !== "" ? wallModel.error : "No wallpapers found in " + wallModel.wallDirs
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; visible: wallModel.walls.length === 0 }

                // Theme pass button
                Components.TextButton {
                    Layout.fillWidth: true
                    text: "Apply theme pass (GTK, kitty, shell)"
                    onClicked: wallModel.runThemePass()
                }
            }
        }
    }

    function isCurrent(path) { return wallModel.current !== "" && wallModel.current === path; }
    function currentLabel() {
        if (wallModel.current === "") return "";
        var parts = wallModel.current.split("/");
        return "Current: " + parts[parts.length - 1];
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
