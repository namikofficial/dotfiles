import QtQuick
import "../theme" as Theme

// Horizontal value bar.
//
// Two modes, one component:
//   interactive (default) — a draggable/keyboard slider that emits moved(value)
//   readOnly: true         — a pure indicator (dashboard CPU/GPU/RAM usage):
//                           no knob, no pointer or key handling, full opacity.
//                           `enabled: false` is NOT usable for this because it
//                           also applies the disabled opacity, and a usage bar
//                           is still meaningful while merely unfocused.
//
// Controlled-component contract, same as Toggle.qml: callers bind `value` to
// their own state and the component NEVER assigns it. Assignment would destroy
// the caller's binding permanently, so the bar would stop tracking any later
// change of its source (a brightness keypress, a volume change from the tray).
// During a drag the local `dragging`/`dragValue` pair drives the painted
// position instead, so the bar still tracks the pointer while the caller
// processes moved() on its own schedule — QuickTab's brightness slider commits
// on a debounce timer, and without this it would visibly freeze mid-drag.
FocusScope {
    id: root
    property real value: 0.5
    property real from: 0
    property real to: 1
    property bool readOnly: false
    property string accessibleName: "Slider"
    // Overrides the filled portion colour, so usage bars can turn red past a
    // threshold without forking the component.
    property color fillColor: Theme.Tokens.tonalPrimary
    signal moved(real value)

    implicitWidth: Theme.Tokens.scaled(240)
    // A read-only bar is a 6px line, not a 44px touch target. Sizing it like an
    // interactive slider silently stole vertical space from rows that sit next
    // to it: in the dashboard's fixed-height tiles the bar pushed the
    // temperature line out of the tile entirely.
    implicitHeight: Theme.Tokens.scaled(root.readOnly
        ? Theme.Tokens.heightSliderTrack
        : Theme.Tokens.heightControl)
    opacity: enabled ? 1.0 : Theme.Tokens.opacityDisabled
    activeFocusOnTab: !root.readOnly
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    // Accessible.value: root.value  // not available in this Qt version

    readonly property int trackHeight: Theme.Tokens.scaled(Theme.Tokens.heightSliderTrack)
    readonly property int knobSize: Theme.Tokens.scaled(Theme.Tokens.sizeSliderKnob)
    readonly property real knobRadius: root.knobSize / 2
    readonly property real stepFraction: 0.04
    // What is actually painted: the caller's value normally, the live drag
    // position while a drag is in flight.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shownValue: root.dragging ? root.dragValue : root.value
    readonly property real fraction: root.to === root.from
        ? 0
        : Math.max(0, Math.min(1, (root.shownValue - root.from) / (root.to - root.from)))
    // Drag travel is shortened by the knob radius at both ends so the knob never
    // hangs off the track.
    readonly property real travel: Math.max(0, root.width - root.knobSize)

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0; width: parent.width
        height: root.trackHeight
        radius: Math.round(root.trackHeight / 2)
        color: Theme.Tokens.outlineSubtle
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: root.readOnly
            ? parent.width * root.fraction
            : root.knobRadius + root.travel * root.fraction
        height: root.trackHeight
        radius: Math.round(root.trackHeight / 2)
        color: root.fillColor
        Behavior on width { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        visible: !root.readOnly
        x: root.knobRadius + root.travel * root.fraction
        anchors.verticalCenter: parent.verticalCenter
        width: root.knobSize; height: root.knobSize
        radius: root.knobRadius
        color: Theme.Tokens.tonalPrimary
        border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"
        border.width: root.activeFocus ? 2 : 0
        Behavior on x { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } } // NOLINT: qmllint
    }

    MouseArea {
        // A read-only bar must not swallow clicks meant for the tile behind it.
        enabled: !root.readOnly
        anchors.fill: parent
        onPressed: {
            root.forceActiveFocus();
            root.dragging = true;
            root.dragValue = root.value;
            root.setFromPosition(mouse.x);
        }
        onPositionChanged: if (pressed) root.setFromPosition(mouse.x)
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
    }
    Keys.onLeftPressed: {
        if (root.enabled && !root.readOnly) root.nudge(-root.stepFraction);
    }
    Keys.onRightPressed: {
        if (root.enabled && !root.readOnly) root.nudge(root.stepFraction);
    }
    // No Keys.onHomePressed/onEndPressed: this Qt build does not expose those
    // handlers, and declaring them makes the whole config fail to load.

    /// Emit a new value without touching the caller's bound `value`.
    function commit(nextFraction) {
        if (!root.enabled || root.readOnly || root.to === root.from) return;
        var clamped = Math.max(0, Math.min(1, nextFraction));
        var next = root.from + clamped * (root.to - root.from);
        if (next === root.shownValue) return;
        root.dragValue = next;
        root.moved(next);
    }

    /// Keyboard nudges start and end a drag around the current value so the
    /// painted bar follows the key instead of snapping back to a stale source.
    function nudge(delta) {
        if (root.to === root.from) return;
        var base = root.dragging ? root.dragValue : root.value;
        root.dragging = true;
        root.commit((base - root.from) / (root.to - root.from) + delta);
    }

    /// Map a pointer x position (0..width) onto the value range.
    function setFromPosition(position) {
        if (root.travel <= 0) return;
        root.commit((position - root.knobRadius) / root.travel);
    }
}