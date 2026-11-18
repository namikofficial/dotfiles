import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Components

// SessionSecurityModel — fail-closed lock state for privacy-sensitive shell UI.
QtObject {
    id: root

    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")
    readonly property int pollIntervalMs: 1000

    // Hide private content until logind confirms that the session is unlocked.
    property bool privacyRedacted: true
    property bool stateAvailable: false

    function refresh() {
        if (probe.running || sessionId === "") return;
        probe.run(["loginctl", "show-session", sessionId, "-p", "LockedHint", "--value"]);
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    property Components.Command probe: Components.Command {
        label: "Session lock state"
        onExited: function (code) {
            var state = root.probe.output.trim();
            if (code === 0 && (state === "yes" || state === "no")) {
                root.stateAvailable = true;
                root.privacyRedacted = state !== "no";
            } else {
                root.stateAvailable = false;
                root.privacyRedacted = true;
            }
            pollTimer.restart();
        }
    }

    property Timer pollingTimer: Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        running: root.sessionId !== ""
        onTriggered: root.refresh()
    }
}
