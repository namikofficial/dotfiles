import QtQuick
import Quickshell.Io
import "../components" as Components

// IslandTimers.qml — the island's four timers and the update launcher.
//
// Extracted from IslandHost.qml. These were interleaved with the view and the
// wiring, which made the host the largest file in the island and pushed the
// Phase 3 "no file over 350 lines" target out of reach.
//
// The clock is the one timer that runs unconditionally: it is the clock. Every
// other periodic source in the shell is event-driven (see decision 9).

Item {
    id: root

    // ── Inputs ──
    required property var host            // IslandHost.qml
    required property var activityController

    /// Clears the dashboard status line after it has been shown.
    property var clearDashboardStatus: null
    /// Retires the island back to idle.
    property var deactivate: null
    /// Seeds the OSD guards and ends startup suppression.
    property var endStartupSuppression: null

    // ── Timer state ──
    /// Set by the timer OSD; the tick only writes the label while the timer is
    /// what the island is showing (Phase 1 item 1.11).
    property bool timerActive: false
    property int timerRemainingSeconds: 0
    property string currentKind: "idle"

    function formatTime(s) {
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // ── Clock ──
    // 1 Hz, for the clock only. It must never write the activity label while a
    // different OSD owns the island — that overwrote volume and brightness
    // notifications with "Timer …".
    Timer {
        id: clockTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.host.now = new Date();
            if (!root.timerActive || root.timerRemainingSeconds <= 0) return;
            if (root.currentKind !== "timer") return;
            root.timerRemainingSeconds--;
            root.host.activityLabel = "Timer " + root.formatTime(root.timerRemainingSeconds);
            if (root.timerRemainingSeconds <= 0) {
                root.timerActive = false;
                if (root.deactivate) root.deactivate();
            }
        }
    }

    Timer {
        id: dashboardStatusTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.clearDashboardStatus) root.clearDashboardStatus();
            var active = root.activityController ? root.activityController.activeActivity : null;
            if (active && active.id) root.activityController.finishActivity(active.id);
        }
    }

    // OSDs stay suppressed until the models have synced, so the first snapshot
    // after startup does not fire a burst of cards for values nobody changed.
    Timer {
        id: startupGuardTimer
        interval: 5000
        repeat: false
        running: true
        onTriggered: {
            if (root.endStartupSuppression) root.endStartupSuppression();
        }
    }

    /// Starts (or restarts) the timer OSD and reports the total to the queue.
    function startTimer(seconds) {
        if (seconds <= 0) return;
        root.timerRemainingSeconds = seconds;
        root.timerActive = true;
        root.host.timerTotalSeconds = seconds;
        root.host.enqueue("timer", "Timer " + root.formatTime(seconds), "", 1, 1,
                          root.host.priTimer, Math.max(1000, seconds * 1000));
    }

    // ── System update ──
    // The island's "updates" route points at a sentinel panel, which means
    // "launch the update terminal" rather than "open a panel the coordinator
    // knows". That distinction lives in IslandRoutes.js; the launch lives here.
    Components.Command {
        id: updateProcess
        label: "System update"
        command: ["sh", "-lc", "exec \"$HOME/.config/hypr/scripts/system-update.sh\""]
    }

    function runSystemUpdate() {
        updateProcess.run(["sh", "-lc", "exec \"$HOME/.config/hypr/scripts/system-update.sh\""]);
    }
}