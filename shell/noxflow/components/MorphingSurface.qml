// MorphingSurface — wraps a PanelWindow to animate its position/size/radius
// from a source chip geometry to the panel's target geometry on open.
// Non-blocking: input accepted from frame 0, animation is cosmetic.
// Stolen from: ilyamiro/nixos-configuration + caelestia-dots/shell morph concept.

import QtQuick
import "../theme" as Theme

QtObject {
    id: root

    // The PanelWindow to morph (must have openProgress, panelOpen, etc.)
    required property Item target

    // Chip ID to morph from (registered in MorphRegistry)
    property string morphFrom: ""
    property bool morphEnabled: true

    // Snapshot of source geometry at open time (prevents mid-morph teleport)
    property rect sourceRect: Qt.rect(0, 0, 0, 0)
    property rect targetRect: Qt.rect(0, 0, 0, 0)
    property bool morphing: false
    property real morphProgress: 0.0

    // Hook into target's open() — call this instead of target.open()
    function openWithMorph() {
        if (!morphEnabled || !morphFrom) {
            target.open();
            return;
        }

        var src = MorphRegistry.chipRect(morphFrom);
        if (src.width === 0 || src.height === 0) {
            target.open();
            return;
        }

        sourceRect = src;
        morphing = true;
        morphProgress = 0.0;

        // Target needs to set its position/size to match chip first
        target.open();
        morphAnim.start();
    }

    // Animate from source to target
    SequentialAnimation {
        id: morphAnim
        NumberAnimation {
            target: root; property: "morphProgress"
            from: 0.0; to: 1.0
            duration: Theme.Tokens.duration(350)
            easing.type: Easing.OutCubic
        }
        onFinished: {
            root.morphing = false;
            root.morphProgress = 1.0;
        }
    }
}
