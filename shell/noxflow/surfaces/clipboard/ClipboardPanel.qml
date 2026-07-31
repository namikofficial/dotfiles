// ClipboardPanel — right-side clipboard history drawer. SUPER+V.
// Keyboard-navigable list of recent clipboard entries with copy/delete/clear.

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
    required property var clipModel

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    implicitWidth: Theme.Tokens.scaled(380)
    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() { list.positionViewAtBeginning(); }
    }

    FocusScope {
        id: focusRoot; focus: lifecycle.interactive; anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")

        Rectangle {
            anchors.fill: parent; radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            border.color: Theme.Tokens.outlineDefault; border.width: 1
            opacity: root.openProgress; scale: 0.9 + 0.1 * root.openProgress
            transformOrigin: Item.TopRight

            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingMd

                // Header
                RowLayout { Layout.fillWidth: true
                    Text { text: "Clipboard"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true; Layout.fillWidth: true }
                    Text { text: "Clear"; color: Theme.Tokens.stateInfo; font.pixelSize: Theme.Tokens.typographyLabelMedium
                        visible: clipModel.count > 0
                        TapHandler { onTapped: clipModel.clearAll() }
                        HoverHandler { cursorShape: Qt.PointingHandCursor } }
                    Components.IconButton { iconText: "\uF00D"; accessibleName: "Close clipboard"; onClicked: lifecycle.requestClose("closeButton") }
                }

                // Empty state
                Text { text: "Clipboard is empty"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodyMedium
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; visible: clipModel.count === 0
                    Layout.topMargin: Theme.Tokens.spacingXl }

                // List
                ListView {
                    id: list
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    model: clipModel.history
                    spacing: Theme.Tokens.spacingXs
                    focus: lifecycle.interactive
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationWraps: true

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: list.width; height: Theme.Tokens.scaled(52)
                        radius: Theme.Tokens.radiusMd
                        color: list.currentIndex === index ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
                        border.color: list.currentIndex === index ? Theme.Tokens.outlineSubtle : "transparent"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                            spacing: Theme.Tokens.spacingMd
                            Text { text: "\uF0EA"; color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconSm }
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                Text { text: root.preview(modelData.text); color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.timeLabel(modelData.timestamp); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                            }
                            Components.IconButton { iconText: "\uF12C"; accessibleName: "Delete entry"; visible: list.currentIndex === index
                                onClicked: clipModel.removeEntry(modelData.id) }
                        }

                        TapHandler { onTapped: { list.currentIndex = index; root.copyEntry(modelData); } }
                        HoverHandler { onHoveredChanged: { if (hovered) list.currentIndex = index; } cursorShape: Qt.PointingHandCursor }
                    }

                    // Keyboard: up/down move, enter copies, delete removes
                    Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
                    Keys.onDownPressed: list.currentIndex = Math.min(clipModel.count - 1, list.currentIndex + 1)
                    Keys.onReturnPressed: { if (list.currentIndex >= 0 && list.currentIndex < clipModel.history.length) root.copyEntry(clipModel.history[list.currentIndex]); }
                    Keys.onDeletePressed: { if (list.currentIndex >= 0 && list.currentIndex < clipModel.history.length) clipModel.removeEntry(clipModel.history[list.currentIndex].id); }

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }
        }
    }

    function preview(text) {
        if (!text) return "";
        var firstLine = String(text).split("\n")[0] || "";
        return firstLine.length > 80 ? firstLine.substring(0, 77) + "..." : firstLine;
    }
    function timeLabel(ts) { return clipModel.formatTime ? clipModel.formatTime(ts) : ""; }

    // ── Copy to clipboard via wl-copy (detached, no shell session) ──
    property Process copyProcess: Process { running: false }

    function copyEntry(entry) {
        if (!entry || !entry.text) return;
        // wl-copy reads the entry from stdin; the text is passed as a JSON
        // string arg to sh -c to avoid injection.
        copyProcess.command = ["sh", "-c", "printf %s \"$1\" | wl-copy --type text/plain", "clipboard-panel", String(entry.text)];
        copyProcess.running = true;
        if (root.noxd && root.noxd.connected) root.noxd.runAction({ clipboard_copy: { text: entry.text } });
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
