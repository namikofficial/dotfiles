import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme" as Theme
import "../../components" as Components
import "." as Local

PanelWindow {
    id: root

    required property var coordinator

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    property bool previewsActive: false

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    color: "transparent"
    visible: lifecycle.active
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "noxflow-atlas"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: lifecycle.active
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Behavior on openProgress {
        NumberAnimation {
            duration: lifecycle.animDuration
            easing.type: lifecycle.easingType
        }
    }

    function open() {
        lifecycle.open();
        Qt.callLater(selectFocusedWorkspace);
    }
    function close() { lifecycle.requestClose("close"); }
    function toggle() {
        if (lifecycle.active) close();
        else open();
    }

    function selectFocusedWorkspace() {
        var focusedWorkspace = Hyprland.focusedWorkspace;
        var focusedId = focusedWorkspace && focusedWorkspace.id !== undefined
            ? Number(focusedWorkspace.id) : NaN;
        for (var i = 0; i < workspaceGrid.count; i++) {
            var card = workspaceGrid.itemAtIndex(i);
            if (!card || !card.workspace) continue;
            var workspaceId = card.workspace.id !== undefined ? Number(card.workspace.id) : NaN;
            var isFocused = card.workspace === focusedWorkspace
                || (!isNaN(focusedId) && !isNaN(workspaceId) && workspaceId === focusedId)
                || card.workspace.focused === true;
            if (isFocused) {
                workspaceGrid.currentIndex = i;
                workspaceGrid.positionViewAtIndex(i, GridView.Contain);
                card.forceActiveFocus();
                return;
            }
        }
        // During the opening transition GridView may not have instantiated
        // its delegates yet. Keep the selection pending until onOpened retries.
        if (focusedWorkspace) return;
        if (workspaceGrid.count > 0) {
            workspaceGrid.currentIndex = 0;
            if (workspaceGrid.currentItem) workspaceGrid.currentItem.forceActiveFocus();
        }
    }

    function stepWorkspace(delta) {
        if (delta === 0) { close(); return; }
        if (workspaceGrid.count === 0) return;
        var next = workspaceGrid.currentIndex + delta;
        if (next < 0) next = workspaceGrid.count - 1;
        if (next >= workspaceGrid.count) next = 0;
        workspaceGrid.currentIndex = next;
        Qt.callLater(function() {
            if (workspaceGrid.currentItem) workspaceGrid.currentItem.forceActiveFocus();
        });
    }

    function focusWindow(client) {
        if (!client || !client.address) return;
        var address = String(client.address);
        if (!/^0x[0-9a-f]+$/i.test(address)) return;
        if (client.workspace && client.workspace.id !== undefined)
            Hyprland.dispatch("workspace " + Number(client.workspace.id));
        Hyprland.dispatch("focuswindow address:" + address);
        close();
    }

    function moveWindow(address, workspace) {
        if (!workspace || workspace.id === undefined || !/^0x[0-9a-f]+$/i.test(address)) return;
        Hyprland.dispatch("movetoworkspacesilent " + Number(workspace.id)
            + ",address:" + address);
    }

    FocusScope {
        id: focusRoot
        anchors.fill: parent
        focus: lifecycle.interactive
        Keys.onEscapePressed: root.close()
        Keys.onTabPressed: root.stepWorkspace(1)
        Keys.onBacktabPressed: root.stepWorkspace(-1)

        Rectangle {
            anchors.fill: parent
            color: Theme.Tokens.surfaceSurfaceCanvas
            opacity: root.openProgress
        }

        ColumnLayout {
            id: atlasLayout
            anchors.fill: parent
            anchors.leftMargin: Math.max(Theme.Tokens.scaled(28), parent.width * 0.06)
            anchors.rightMargin: Math.max(Theme.Tokens.scaled(28), parent.width * 0.06)
            anchors.topMargin: Math.max(Theme.Tokens.scaled(24), parent.height * 0.055)
            anchors.bottomMargin: Math.max(Theme.Tokens.scaled(24), parent.height * 0.055)
            spacing: Theme.Tokens.scaled(22)
            opacity: root.openProgress
            scale: 0.985 + root.openProgress * 0.015
            transformOrigin: Item.Center

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(18)

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: "NOX / ATLAS"
                        color: Theme.Tokens.tonalSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.bold: true
                        font.letterSpacing: Theme.Tokens.scaled(1.4)
                    }
                    Text {
                        text: "Your work, in view."
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyDisplayFamily
                        font.pixelSize: Theme.Tokens.scaled(32)
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "← → choose a space     Tab next space     ↵ focus     Esc close"
                    color: Theme.Tokens.textMuted
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelMedium
                    horizontalAlignment: Text.AlignRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.Tokens.outlineSubtle
            }

            GridView {
                id: workspaceGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Hyprland.workspaces
                cellWidth: width < Theme.Tokens.scaled(900)
                    ? width : Math.floor((width - Theme.Tokens.scaled(18)) / 2)
                cellHeight: {
                    var columns = width < Theme.Tokens.scaled(900) ? 1 : 2;
                    var rows = Math.max(1, Math.ceil(workspaceGrid.count / columns));
                    var heightPerRow = Math.floor(height / rows);
                    return Math.max(Theme.Tokens.scaled(380),
                        Math.min(Theme.Tokens.scaled(410), heightPerRow));
                }
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                keyNavigationEnabled: false
                currentIndex: -1
                onCurrentIndexChanged: {
                    if (currentItem && lifecycle.active)
                        Qt.callLater(function() { if (workspaceGrid.currentItem) workspaceGrid.currentItem.forceActiveFocus(); });
                }

                delegate: Local.AtlasWorkspace {
                    required property var modelData
                    required property int index
                    workspace: modelData
                    workspaceIndex: index
                    overviewOpen: root.previewsActive
                    width: workspaceGrid.cellWidth - Theme.Tokens.scaled(10)
                    height: workspaceGrid.cellHeight - Theme.Tokens.scaled(10)
                    selected: index === workspaceGrid.currentIndex
                    onActivateWindow: function(client) { root.focusWindow(client); }
                    onMoveWindow: function(address, targetWorkspace) { root.moveWindow(address, targetWorkspace); }
                    onRequestWorkspaceStep: function(delta) { root.stepWorkspace(delta); }
                    Component.onCompleted: {
                        if (workspace.focused && lifecycle.active) {
                            workspaceGrid.currentIndex = index;
                            forceActiveFocus();
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: workspaceGrid.count === 0
                    text: "No workspaces available"
                    color: Theme.Tokens.textMuted
                    font.family: Theme.Tokens.typographyDisplayFamily
                    font.pixelSize: Theme.Tokens.typographyTitleLarge
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (lifecycle.active) Qt.callLater(root.selectFocusedWorkspace);
        }
    }

    Connections {
        target: lifecycle
        function onOpened() {
            root.previewsActive = true;
            Qt.callLater(root.selectFocusedWorkspace);
        }
        function onClosing() { root.previewsActive = false; }
        function onClosed() { root.previewsActive = false; }
    }

    Component.onCompleted: root.coordinator.registerModal(root)
    Component.onDestruction: root.coordinator.unregisterModal(root)
}
