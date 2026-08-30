import QtQuick
import "../../../theme" as Theme

// Vertical slider for volume control — used in the island.
Item {
    id: root

    property real value: 0
    property real maximum: 100
    property string accent: Theme.Tokens.tonalPrimary
    property bool active: false
    signal sliderDragged(real fraction)

    width: Theme.Tokens.scaled(24)

    // Track
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: Theme.Tokens.outlineSubtle

        // Fill
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height * Math.min(1, Math.max(0, root.value / root.maximum))
            radius: parent.radius
            color: root.accent
        }

        // Knob
        Rectangle {
            x: parent.x - 6
            y: parent.y + parent.height * (1 - Math.min(1, Math.max(0, root.value / root.maximum))) - 8
            width: 16
            height: 16
            radius: 8
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            border.color: Theme.Tokens.outlineDefault
            border.width: 1
        }
    }

    // Drag area
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        function valueFromMouse(mouseY) {
            return Math.max(0, Math.min(1, 1 - mouseY / height));
        }

        onPressed: function(mouse) {
            root.active = true;
            var v = valueFromMouse(mouse.y);
            root.value = v * root.maximum;
            root.sliderDragged(v);
        }
        onPositionChanged: function(mouse) {
            if (!root.active) return;
            var v = valueFromMouse(mouse.y);
            root.value = v * root.maximum;
            root.sliderDragged(v);
        }
        onReleased: {
            root.active = false;
        }
    }
}
