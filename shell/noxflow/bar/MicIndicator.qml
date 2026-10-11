import QtQuick
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "." as Local
import "../components" as Components

// MicIndicator.qml — shows when an application is capturing from a microphone.
//
// There was no indicator at all: a screen recorder, a call or a voice assistant
// could open the mic with nothing on the bar to say so.
//
// Detection is a single `pactl list sources` read: a source an application is
// currently capturing from reports State: RUNNING.
//
// Two traps this had to avoid:
//   - A monitor source (`*.monitor`) reports RUNNING whenever playback is
//     active, so matching on State alone lit the indicator for ordinary audio
//     output. Monitors are filtered out.
//   - The block's friendly label is on `Name:`, not on the `Source #NN` line
//     the state is attached to, so the state has to be buffered and matched
//     after the name is seen.



Local.BarStatusPill {
    id: root

    // A microphone that is merely present is not news; only a capture in
    // progress gets a permanent slot in the bar.
    visible: root.micInUse
    occupied: true
    minimumWidth: Theme.Tokens.scaled(40)
    horizontalPadding: Theme.Tokens.scaled(10)
    tooltipText: "Microphone in use" + (root.captureNames.length > 0 ? " by " + root.captureNames.join(", ") : "")

    property bool micInUse: false
    property var captureNames: []

    readonly property int pollIntervalMs: 4000

    function poll() {
        if (probe.running) return;
        captureNames = [];
        probe.runShell(
            "pactl list sources 2>/dev/null | awk -F': *' "
            + "'/^Source:/ { state=\"\" } "
            + "/^\\s*State:/ { state=$2 } "
            + "/^\\s*Name:/ { if (state == \"RUNNING\" && $2 !~ /\\.monitor$/) print $2 }'");
    }

    // Deferred: the poll restarts `pollTimer`, which is declared after this
    // component. Calling poll() synchronously from onCompleted ran against an
    // undefined timer ("Cannot call method 'restart' of undefined").
    Component.onCompleted: Qt.callLater(root.poll)

    property Components.Command probe: Components.Command {
        label: "Microphone probe"
        onExited: function (code) {
            if (code === 0) {
                // The awk output is a newline-separated list of source names.
                root.captureNames = root.probe.output.split("\n")
                    .map(function(line) { return String(line).trim() })
                    .filter(function(line) { return line !== ""; });
                root.micInUse = root.captureNames.length > 0;
            } else {
                // No pactl, or no audio server. Hide rather than show a
                // permanently wrong "in use" dot.
                root.micInUse = false;
                root.captureNames = [];
            }
            pollTimer.restart();
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    Text {
        text: ""
        color: Theme.Tokens.stateDanger
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
}