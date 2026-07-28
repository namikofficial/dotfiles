// SurfaceLifecycle — consistent state machine for every NoxFlow surface.
//
// States: Closed → Opening → Open → Closing → Closed
//                  ↑___________________________↓  (toggle reverses mid-transition)
//
// Each surface adds a Behavior on openProgress to animate scale/opacity.
// The lifecycle only drives the completion timer and state transitions.
//
// Usage:
//   PanelWindow {
//       SurfaceLifecycle { id: lifecycle }
//       visible: lifecycle.active
//       property alias openProgress: lifecycle.openProgress
//       Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }
//       FocusScope { focus: lifecycle.interactive; Keys.onEscapePressed: lifecycle.requestClose("escape") }
//       function toggle() { lifecycle.toggle() }
//       function open()   { lifecycle.open() }
//       function close()  { lifecycle.requestClose("close") }
//   }

import QtQuick
import "../theme" as Theme

QtObject {
    id: root

    enum State { Closed, Opening, Open, Closing }

    // ── Public state ──
    property int state: SurfaceLifecycle.State.Closed
    property real openProgress: 0
    readonly property bool active: state !== SurfaceLifecycle.State.Closed
    readonly property bool interactive: state === SurfaceLifecycle.State.Open
    readonly property bool transitioning: completionTimer.running
    property string closeReason: ""
    readonly property int animDuration: Theme.Tokens.duration(220)

    // The type of easing the surface's Behavior should use
    readonly property int easingType: state === SurfaceLifecycle.State.Opening
        ? Easing.OutCubic
        : Easing.InCubic

    // ── Signals ──
    signal opened()
    signal closed()
    signal closing(string reason)

    // ── Timer-based completion ──
    // Animations are driven by Behavior on the surface Item, not from here.
    // This timer matches the Behavior duration so we fire opened()/closed()
    // when the visual transition completes.
    // Declared as a property Timer so it's valid inside QtObject (no default property).
    property Timer completionTimer: Timer {
        interval: root.animDuration
        repeat: false
        onTriggered: root.finalize()
    }

    function finalize() {
        if (root.state === SurfaceLifecycle.State.Opening) {
            root.state = SurfaceLifecycle.State.Open;
            root.opened();
        } else if (root.state === SurfaceLifecycle.State.Closing) {
            root.state = SurfaceLifecycle.State.Closed;
            root.closed();
        }
    }

    // ── API ──

    function open() {
        if (root.state === SurfaceLifecycle.State.Open ||
            root.state === SurfaceLifecycle.State.Opening) return;

        completionTimer.stop();

        if (root.state === SurfaceLifecycle.State.Closing) {
            root.closeReason = "";
            root.state = SurfaceLifecycle.State.Opening;
            root.openProgress = 1.0;
            completionTimer.restart();
            return;
        }

        root.closeReason = "";
        root.state = SurfaceLifecycle.State.Opening;
        root.openProgress = 1.0;
        completionTimer.restart();
    }

    function close() {
        if (root.state === SurfaceLifecycle.State.Closed ||
            root.state === SurfaceLifecycle.State.Closing) return;

        completionTimer.stop();

        if (root.state === SurfaceLifecycle.State.Opening) {
            root.state = SurfaceLifecycle.State.Closing;
            root.closing(root.closeReason || "reverse");
            root.openProgress = 0.0;
            completionTimer.restart();
            return;
        }

        root.state = SurfaceLifecycle.State.Closing;
        root.closing(root.closeReason || "close");
        root.openProgress = 0.0;
        completionTimer.restart();
    }

    function requestClose(reason) {
        if (root.state !== SurfaceLifecycle.State.Open &&
            root.state !== SurfaceLifecycle.State.Opening) return;
        root.closeReason = reason || "request";
        close();
    }

    function toggle() {
        if (root.state === SurfaceLifecycle.State.Closed ||
            root.state === SurfaceLifecycle.State.Closing) {
            open();
        } else {
            requestClose("toggle");
        }
    }
}
