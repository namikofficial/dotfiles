import QtQuick
import "../theme" as Theme

FocusScope {
    id: root
    property real value: 0.5
    property real from: 0
    property real to: 1
    property string accessibleName: "Slider"
    signal moved(real value)
    implicitWidth: 240
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightControl)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    // Accessible.value: root.value  // not available in this Qt version
    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: parent.width; height: 4; radius: 2; color: Theme.Tokens.outlineSubtle }
    Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: Math.max(0, root.width * ((root.value - root.from) / (root.to - root.from))); height: 4; radius: 2; color: Theme.Tokens.tonalPrimary }
    Rectangle { x: Math.max(0, Math.min(root.width - 20, root.width * ((root.value - root.from) / (root.to - root.from)) - 10)); anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 10; color: root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.tonalPrimary }
    MouseArea {
        anchors.fill: parent
        onPressed: {
            root.forceActiveFocus();
            root.setFromPosition(mouse.x);
        }
        onPositionChanged: if (pressed) root.setFromPosition(mouse.x)
    }
    Keys.onLeftPressed: {
        if (root.enabled) root.setFromPosition(root.width * ((root.value - root.from) / (root.to - root.from)) - 8);
    }
    Keys.onRightPressed: {
        if (root.enabled) root.setFromPosition(root.width * ((root.value - root.from) / (root.to - root.from)) + 8);
    }
    Keys.onSpacePressed: {
        if (root.enabled) root.setFromPosition(root.width * ((root.value - root.from) / (root.to - root.from)));
    }
    function setFromPosition(position) {
        if (!root.enabled || root.width <= 0 || root.to <= root.from) return;
        var next = root.from + (Math.max(0, Math.min(root.width, position)) / root.width) * (root.to - root.from);
        root.value = next;
        root.moved(next);
    }
}
