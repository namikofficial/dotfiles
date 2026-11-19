import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme" as Theme
import "." as Local

FocusScope {
    id: root

    required property var workspace
    required property int workspaceIndex
    property bool selected: false
    property int selectedWindowIndex: 0
    property bool overviewOpen: false

    signal activateWindow(var client)
    signal moveWindow(string address, var workspace)
    signal requestWorkspaceStep(int delta)

    readonly property int windowCount: windowGrid.count
    readonly property string workspaceLabel: workspace
        ? (workspace.name || String(workspace.id)) : "Workspace"

    implicitWidth: Theme.Tokens.scaled(760)
    implicitHeight: Theme.Tokens.scaled(370)
    activeFocusOnTab: true
    Accessible.role: Accessible.Grouping
    Accessible.name: workspaceLabel + ", " + windowCount + " windows"

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusLg
        color: Theme.Tokens.surfaceSurfaceBase
        border.color: root.selected ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineSubtle
        border.width: root.selected ? 2 : 1
    }

    DropArea {
        anchors.fill: parent
        onEntered: root.dropTargeted = true
        onExited: root.dropTargeted = false
        onDropped: function(drop) {
            root.dropTargeted = false;
            if (drop.source && drop.source.address)
                root.moveWindow(String(drop.source.address), root.workspace);
        }
    }

    property bool dropTargeted: false

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusLg
        color: root.dropTargeted ? Theme.Tokens.glass(Theme.Tokens.tonalSecondary, 0.12) : "transparent"
        border.color: root.dropTargeted ? Theme.Tokens.tonalSecondary : "transparent"
        border.width: root.dropTargeted ? 2 : 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.Tokens.scaled(16)
        spacing: Theme.Tokens.scaled(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.scaled(10)

            Rectangle {
                width: Theme.Tokens.scaled(8)
                height: width
                radius: width / 2
                color: root.workspace && root.workspace.focused
                    ? Theme.Tokens.tonalSecondary : Theme.Tokens.outlineStrong
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.workspaceLabel
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyDisplayFamily
                font.pixelSize: Theme.Tokens.typographyTitleLarge
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: String(root.windowCount).padStart(2, "0")
                color: Theme.Tokens.textMuted
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
            }

            Text {
                visible: root.workspace && root.workspace.focused
                text: "CURRENT"
                color: Theme.Tokens.tonalSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                font.bold: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.Tokens.outlineSubtle
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: windowGrid
                anchors.fill: parent
                clip: true
                model: root.workspace ? root.workspace.toplevels : null
                currentIndex: root.selected ? root.selectedWindowIndex : -1
                cellWidth: root.windowCount === 1
                    ? width : Math.floor((width - Theme.Tokens.scaled(10)) / 2)
                // Give the previews the available space. The former fixed
                // 280px ceiling left the lower half of large workspaces empty.
                cellHeight: Math.max(Theme.Tokens.scaled(160),
                    Math.floor(height / Math.max(1, Math.ceil(root.windowCount / 2))))
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                focus: root.selected
                keyNavigationEnabled: true
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: {
                    if (root.selected && currentIndex >= 0)
                        root.selectedWindowIndex = currentIndex;
                }

                delegate: Local.AtlasWindow {
                    required property var modelData
                    required property int index
                    client: modelData
                    width: windowGrid.cellWidth - Theme.Tokens.scaled(8)
                    height: windowGrid.cellHeight - Theme.Tokens.scaled(8)
                    selected: root.selected && index === root.selectedWindowIndex
                    overviewOpen: root.overviewOpen
                    live: root.overviewOpen && visible && selected
                    onActivated: function(client) { root.activateWindow(client); }
                }

                Keys.onReturnPressed: {
                    if (currentItem && currentItem.client)
                        root.activateWindow(currentItem.client);
                }
                Keys.onEnterPressed: {
                    if (currentItem && currentItem.client)
                        root.activateWindow(currentItem.client);
                }
                Keys.onSpacePressed: {
                    if (currentItem && currentItem.client)
                        root.activateWindow(currentItem.client);
                }
                Keys.onEscapePressed: root.requestWorkspaceStep(0)
            }

            Text {
                anchors.centerIn: parent
                visible: root.windowCount === 0
                text: "An open space"
                color: Theme.Tokens.textMuted
                font.family: Theme.Tokens.typographyDisplayFamily
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }
        }
    }

    Keys.onTabPressed: root.requestWorkspaceStep(1)
    Keys.onBacktabPressed: root.requestWorkspaceStep(-1)
    Keys.onEscapePressed: root.requestWorkspaceStep(0)
}
