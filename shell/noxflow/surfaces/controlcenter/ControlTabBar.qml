import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "../../components" as Components

// ControlTabBar — the tab strip above the control centre content.
//
// Extracted from ControlCentre.qml (1531 lines). It was previously hidden
// outright (`visible: false`); that stays here rather than in the host so the
// reason travels with the widget.

Flickable {
    // The owning ControlCentre; `activeTab` is the only thing the bar
    // needs, and reading it through the host keeps the tab list and the
    // selected index from drifting apart.
    required property var host
    id: tabScroller
    visible: false
    Layout.fillWidth: true
    height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    clip: true
    contentWidth: tabRow.implicitWidth
    interactive: contentWidth > width
    Row {
        id: tabRow
        spacing: Theme.Tokens.spacingXs
        Repeater {
            model: ["Quick", "Audio", "Net", "BT", "System", "Input", "Power"]
            delegate: Rectangle {
                required property int index
                required property string modelData
                width: tabLabel.implicitWidth + Theme.Tokens.scaled(20)
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                radius: Theme.Tokens.radiusPill
                color: host.state.activeTab === index ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                border.color: host.state.activeTab === index ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                border.width: 1
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData + " tab"
                Accessible.description: host.state.activeTab === index ? "Selected" : ""
                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: host.state.activeTab === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    font.family: Theme.Tokens.typographyFontFamily
                }
                TapHandler { onTapped: { host.state.activeTab = index; parent.forceActiveFocus(); } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Keys.onReturnPressed: host.state.activeTab = index
                Keys.onSpacePressed: host.state.activeTab = index
                Keys.onLeftPressed: host.state.activeTab = Math.max(0, index - 1)
                Keys.onRightPressed: host.state.activeTab = Math.min(6, index + 1)
            }
        }
    }
}
