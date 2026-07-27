// Workspace Overview — scrollable workspace grid with window previews.
// Stolen from: end-4 + hyprland-scroll-overview (kinetic scroll concept).
// Super+Tab to open, scroll through workspaces, click to focus.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var hyprland

    // ── State ──
    property bool overviewOpen: false
    property real openProgress: 0
    property int selectedWorkspace: -1
    property var workspaceList: []
    property real cellWidth: Theme.Tokens.scaled(280)
    property real cellHeight: Theme.Tokens.scaled(200)
    property real cellGap: Theme.Tokens.scaled(Theme.Tokens.spacingMd)

    // ── Window ──
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: overviewOpen

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.75)
        opacity: root.openProgress
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(200) } }
        TapHandler { onTapped: root.close() }
    }

    // ── Workspace grid (horizontal Flickable for kinetic scroll) ──
    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: Theme.Tokens.scaled(Theme.Tokens.spacingXxl)
        contentWidth: flow.width
        contentHeight: flow.height
        opacity: root.openProgress
        clip: true
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2500

        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(200) } }

        // Smooth scroll on wheel
        WheelHandler {
            onWheel: function(event) {
                var delta = event.angleDelta.y;
                if (delta !== 0) {
                    scrollAnim.to = Math.max(0, Math.min(flickable.contentWidth - flickable.width, flickable.contentX - delta));
                    scrollAnim.start();
                }
            }
        }

        NumberAnimation {
            id: scrollAnim
            target: flickable
            property: "contentX"
            duration: Theme.Tokens.duration(350)
            easing.type: Easing.OutCubic
        }

        Flow {
            id: flow
            width: parent.width
            spacing: root.cellGap

            Repeater {
                model: root.workspaceList

                delegate: Rectangle {
                    required property int index
                    required property var modelData

                    width: root.cellWidth
                    height: root.cellHeight
                    radius: Theme.Tokens.radiusLg
                    color: index === root.selectedWorkspace ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainerHigh
                    border.color: index === root.selectedWorkspace ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineDefault
                    border.width: index === root.selectedWorkspace ? 2 : 1
                    opacity: root.openProgress
                    scale: 1.0
                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation { duration: Theme.Tokens.duration(100) }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingMd
                        spacing: Theme.Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingSm

                            Rectangle {
                                width: Theme.Tokens.scaled(Theme.Tokens.iconSm)
                                height: Theme.Tokens.scaled(Theme.Tokens.iconSm)
                                radius: width / 2
                                color: modelData.active ? Theme.Tokens.stateSuccess : index === root.selectedWorkspace ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                            }

                            Text {
                                text: modelData.name || ("Workspace " + (index + 1))
                                color: index === root.selectedWorkspace ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary
                                font.family: Theme.Tokens.typographyFontFamily
                                font.pixelSize: Theme.Tokens.typographyTitleMedium
                                font.bold: modelData.active
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.windows ? modelData.windows.length : 0
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                visible: (modelData.windows && modelData.windows.length > 0)
                            }
                        }

                        // Window list
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.Tokens.spacingXs
                            clip: true

                            Repeater {
                                model: modelData.windows || []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent ? parent.width : 0
                                    height: Theme.Tokens.scaled(Theme.Tokens.heightChip - 4)
                                    radius: Theme.Tokens.radiusSm
                                    color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainer, 0.5)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingSm
                                        spacing: Theme.Tokens.spacingSm
                                        Text {
                                            text: "▭"
                                            color: Theme.Tokens.tonalPrimary
                                            font.pixelSize: Theme.Tokens.iconXs
                                        }
                                        Text {
                                            text: modelData.title || modelData.class || "Window"
                                            color: Theme.Tokens.textPrimary
                                            font.family: Theme.Tokens.typographyFontFamily
                                            font.pixelSize: Theme.Tokens.typographyBodySmall
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            Text {
                                text: "Empty"
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                                visible: !modelData.windows || modelData.windows.length === 0
                                anchors.centerIn: parent
                            }
                        }
                    }

                    // ── Interaction ──
                    TapHandler {
                        onTapped: {
                            root.selectedWorkspace = index;
                            root.activateWorkspace(index);
                        }
                    }
                    HoverHandler {
                        onHoveredChanged: { if (hovered) root.selectedWorkspace = index; }
                        cursorShape: Qt.PointingHandCursor
                    }

                    Keys.onReturnPressed: root.activateWorkspace(index)
                }
            }
        }
    }

    // ── Keyboard navigation ──
    Item {
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: root.navigateWorkspace(-1)
        Keys.onRightPressed: root.navigateWorkspace(1)
        Keys.onUpPressed: root.navigateWorkspace(-Math.floor(parent.width / (root.cellWidth + root.cellGap)) || -1)
        Keys.onDownPressed: root.navigateWorkspace(Math.floor(parent.width / (root.cellWidth + root.cellGap)) || 1)
        Keys.onReturnPressed: { if (root.selectedWorkspace >= 0) root.activateWorkspace(root.selectedWorkspace); }
        Keys.onEscapePressed: root.close()
        Keys.onSpacePressed: { if (root.selectedWorkspace >= 0) root.activateWorkspace(root.selectedWorkspace); }
    }

    function navigateWorkspace(delta) {
        if (workspaceList.length === 0) return;
        if (selectedWorkspace < 0) selectedWorkspace = 0;
        else selectedWorkspace = Math.max(0, Math.min(workspaceList.length - 1, selectedWorkspace + delta));

        // Scroll selected workspace into view
        var targetX = selectedWorkspace * (root.cellWidth + root.cellGap) - (flickable.width - root.cellWidth) / 2;
        scrollAnim.to = Math.max(0, Math.min(flickable.contentWidth - flickable.width, targetX));
        scrollAnim.start();
    }

    // ── Build workspace list from hyprland model ──
    function refreshWorkspaces() {
        if (!hyprland || !hyprland.workspaces) {
            workspaceList = [];
            return;
        }

        var list = [];
        for (var i = 0; i < hyprland.workspaces.length; i++) {
            var ws = hyprland.workspaces[i];
            var name = ws.name || String(ws.id || (i + 1));
            if (name.indexOf("special:") === 0) continue;

            var windows = [];
            if (hyprland.windows) {
                for (var w = 0; w < hyprland.windows.length; w++) {
                    var win = hyprland.windows[w];
                    var winWs = win.workspace;
                    var wsName = winWs && (winWs.name || String(winWs.id || ""));
                    if (wsName === name) {
                        windows.push({
                            title: win.title || "",
                            class: win.class || "",
                            address: win.address || ""
                        });
                    }
                }
            }

            list.push({
                name: name,
                id: ws.id,
                active: String(ws.id) === String(hyprland.activeWorkspace?.id || "") || name === String(hyprland.activeWorkspace?.name || ""),
                windows: windows,
                monitor: ws.monitor || ""
            });
        }

        list.sort(function(a, b) { return (a.id || 0) - (b.id || 0); });
        workspaceList = list;

        for (var j = 0; j < list.length; j++) {
            if (list[j].active) { selectedWorkspace = j; return; }
        }
        selectedWorkspace = 0;
    }

    function activateWorkspace(index) {
        if (index < 0 || index >= workspaceList.length) return;
        var ws = workspaceList[index];
        if (root.noxd && root.noxd.connected) {
            root.noxd.runAction({ workspace_focus: { workspace: ws.name || String(ws.id || "") } });
        }
        root.close();
    }

    // ── Public API ──
    function open() {
        refreshWorkspaces();
        overviewOpen = true;
        openProgress = 1;
    }

    function close() {
        closeAnim.start();
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "openProgress"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
        onFinished: root.overviewOpen = false
    }

    function toggle() {
        if (overviewOpen) close(); else open();
    }
}
