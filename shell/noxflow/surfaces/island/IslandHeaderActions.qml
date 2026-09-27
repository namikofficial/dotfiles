import QtQuick
import QtQuick.Layouts
import "../../components" as Components

RowLayout {
    id: root
    property bool pinned: false
    property bool canOpen: false
    signal pinClicked()
    signal openClicked()
    signal closeClicked()
    spacing: 2

    Components.IconButton {
        iconText: "\uF08D"
        checked: root.pinned
        accessibleName: root.pinned ? "Unpin dashboard" : "Pin dashboard"
        onClicked: root.pinClicked()
    }
    Components.IconButton {
        visible: root.canOpen
        iconText: "\uF35D"
        accessibleName: "Open full panel"
        onClicked: root.openClicked()
    }
    Components.IconButton {
        iconText: "\uF00D"
        accessibleName: "Close dashboard"
        onClicked: root.closeClicked()
    }
}
