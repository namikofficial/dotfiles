// Nox Island — dynamic live-activity OSD with priority queue, pill→card transitions, and reduced-motion support.
// Auto-hides after per-activity timeout. Handles: volume, brightness, media, notifications, timers,
// mic/recording, file transfers, AI completion, build/test results, and battery/network warnings.

import QtQuick; import QtQuick.Layouts; import Quickshell; import Quickshell.Wayland
import "theme" as Theme; import "components" as Components; import "surfaces/island" as Island

PanelWindow {
    id: root;

    required property var noxd; required property var audio; required property var brightness

    // ── Valid activity states ──
    readonly property var validStates: ["idle","volume","brightness","media","mic","recording","timer","notification","output-mute","input-mute","file-transfer","ai-completion","build-result","battery-warning","network-warning"]

    // ── Island state ──
    property string islandState: "idle"
    property bool rendered: false
    property bool expanded: false
    property bool reducedMotion: Theme.Tokens.reducedMotion

    // ── Activity data ──
    property string activityLabel: ""
    property string activityIcon: ""
    property real activityValue: 0
    property real activityMaximum: 100
    property string activityDetail: ""

    // Media
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaArtwork: ""
    property string mediaStatus: ""
    property bool mediaAvailable: false

    // Timer
    property int timerTotalSeconds: 0
    property int timerRemainingSeconds: 0
    property bool timerActive: false

    // File transfer
    property string fileTransferName: ""
    property real fileTransferProgress: 0
    property bool fileTransferActive: false

    // AI / Build
    property string aiCompletionText: ""
    property string buildResultText: ""
    property int buildResultStatus: 0 // 0=none, 1=success, 2=fail

    // Derived
    property int displayPercent: Math.round(activityMaximum > 0 ? (activityValue/activityMaximum*100) : activityValue)
    property int lastOutputVolume: audio.outputVolume
    property bool lastOutputMuted: audio.outputMuted
    property bool lastInputMuted: audio.inputMuted
    property bool sliderDragging: false
    property real sliderTarget: -1

    // ── Priority queue ──
    property var activityQueue: []  // [{kind, label, icon, value, maximum, priority, timeout, timestamp}]
    property string currentActivityKind: "idle"
    property int currentActivityPriority: 0
    property double currentActivityStarted: 0

    // ── Activity priority levels ──
    readonly property int priorityTimer: 9
    readonly property int priorityRecording: 9
    readonly property int priorityNotification: 8
    readonly property int priorityAiCompletion: 7
    readonly property int priorityBuildResult: 7
    readonly property int priorityFileTransfer: 6
    readonly property int priorityMedia: 5
    readonly property int priorityBatteryWarning: 8
    readonly property int priorityNetworkWarning: 8
    readonly property int priorityVolume: 3
    readonly property int priorityBrightness: 3
    readonly property int priorityOutputMute: 4
    readonly property int priorityInputMute: 4

    // ── Guards to debounce daemon event spam ──
    property real guardVolume: -1
    property real guardBrightness: -1
    property int cooldownUntil: 0
    property var lastEventKeys: ({})  // provider+type → timestamp, for dedup

    // ── Window sizing (responsive) ──
    screen: root.screen
    visible: rendered
    width: rendered && screen ? screen.width : 0
    height: rendered && expanded ? Theme.Tokens.scaled(76) : rendered ? Theme.Tokens.scaled(36) : 0

    readonly property real pillWidth: Theme.Tokens.scaled(200)
    readonly property real expandedWidth: screen ? Math.min(screen.width * 0.45, Theme.Tokens.scaled(450)) : Theme.Tokens.scaled(450)

    implicitWidth: expanded ? expandedWidth : pillWidth

    Behavior on implicitWidth {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }
    Behavior on height {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }
    Behavior on width {
        enabled: !root.reducedMotion
        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
    }

    Component.onCompleted: {
        rendered = false;
        islandState = "idle";
        currentActivityKind = "idle";
        guardVolume = audio.outputVolume;
        guardBrightness = brightness.percentage;
    }

    // ── Priority queue management ──

    function enqueueActivity(kind, label, icon, value, maximum, priority, timeout) {
        // Deduplicate: skip if same kind+label already in queue with same value
        var eventKey = kind + "::" + label;
        var now = Date.now();
        if (lastEventKeys[eventKey] && (now - lastEventKeys[eventKey]) < 300) return;
        lastEventKeys[eventKey] = now;

        // Remove existing entries of the same kind
        activityQueue = activityQueue.filter(function(e) { return e.kind !== kind; });

        // Add new entry at the front
        activityQueue.unshift({
            kind: kind,
            label: label,
            icon: icon,
            value: value,
            maximum: maximum,
            priority: priority,
            timeout: timeout,
            timestamp: now
        });

        // Sort by priority descending
        activityQueue.sort(function(a, b) { return b.priority - a.priority; });

        // Process the highest-priority item
        processQueue();
    }

    function processQueue() {
        if (activityQueue.length === 0) {
            // Nothing to show — hide after grace period
            if (currentActivityKind !== "idle") {
                hideTimer.interval = 500;
                hideTimer.restart();
            }
            return;
        }

        var top = activityQueue[0];
        // Only switch if higher priority or same kind (refresh)
        if (top.priority < currentActivityPriority && top.kind !== currentActivityKind && currentActivityKind !== "idle") {
            // Lower priority and we're showing something — wait for current to expire
            return;
        }

        // Remove from queue and display
        activityQueue.shift();
        displayActivity(top);
    }

    function displayActivity(entry) {
        currentActivityKind = entry.kind;
        currentActivityPriority = entry.priority;
        currentActivityStarted = Date.now();

        islandState = entry.kind;
        activityLabel = entry.label;
        activityIcon = entry.icon;
        activityValue = Math.max(0, entry.value);
        activityMaximum = Math.max(1, entry.maximum);

        // Determine if expanded card or compact pill
        expanded = shouldExpand(entry.kind);

        rendered = true;
        hideTimer.stop();
        hideTimer.interval = entry.timeout;
        hideTimer.restart();
    }

    function shouldExpand(kind) {
        // Media, notification, timer, file transfer, AI, build result get expanded cards
        return ["media", "notification", "timer", "file-transfer", "ai-completion", "build-result", "recording"].indexOf(kind) >= 0;
    }

    function deactivate() {
        rendered = false;
        islandState = "idle";
        currentActivityKind = "idle";
        currentActivityPriority = 0;
        currentActivityStarted = 0;
        guardVolume = audio.outputVolume;
        guardBrightness = brightness.percentage;
        // Check queue for any pending items
        processQueue();
    }

    // ── Event handlers ──

    // Daemon events
    Connections {
        target: noxd
        function onEventReceived(e) {
            if (!e || !e.provider) return;

            // Audio
            if (e.provider === "audio" && e.data) {
                var v = Number(e.data.output_volume);
                if (isFinite(v)) {
                    lastOutputVolume = v;
                    lastOutputMuted = e.data.output_muted === true;
                    lastInputMuted = e.data.input_muted === true;
                }
                if (isFinite(v) && Math.abs(v - guardVolume) > 1) {
                    guardVolume = v;
                    root.enqueueActivity("volume","Volume","\uF028",v,100,root.priorityVolume,2000);
                } else if (e.data.output_muted !== undefined && e.data.output_muted !== lastOutputMuted) {
                    root.enqueueActivity("output-mute", e.data.output_muted ? "Muted":"Unmuted", e.data.output_muted ? "\uF026":"\uF028", v||0, 100, root.priorityOutputMute, 2000);
                } else if (e.data.input_muted !== undefined && e.data.input_muted !== lastInputMuted) {
                    root.enqueueActivity("input-mute", e.data.input_muted ? "Mic Muted":"Mic Live", "\uF130", 0, 1, root.priorityInputMute, 2000);
                }
                return;
            }

            // Brightness
            if (e.provider === "brightness" && e.data) {
                var b = Number(e.data.percentage);
                if (isFinite(b) && Math.abs(b - guardBrightness) > 1) {
                    guardBrightness = b;
                    root.enqueueActivity("brightness","Brightness","\uF185",b,100,root.priorityBrightness,2000);
                }
                return;
            }

            // Media
            if (e.provider === "media") {
                var md = e.data || {};
                if (md.playback_status === "playing" || md.title) {
                    mediaTitle = md.title||"";
                    mediaArtist = md.artists ? (Array.isArray(md.artists) ? md.artists.join(", ") : String(md.artists)) : "";
                    mediaArtwork = md.artwork_url||md.artwork_cache||"";
                    mediaStatus = md.playback_status||"";
                    mediaAvailable = true;
                    root.enqueueActivity("media",mediaTitle,"\uF001",50,100,root.priorityMedia,5000);
                } else if (md.playback_status === "stopped" || !md.title) {
                    mediaAvailable = false;
                }
                return;
            }

            // Notifications
            if (e.provider === "notifications") {
                var nd = e.data||{};
                root.enqueueActivity("notification",nd.summary||nd.app_name||"Notification","\uF0F3",1,1,root.priorityNotification,5000);
                return;
            }

            // Battery warnings
            if (e.provider === "power") {
                var pd = e.data||{};
                if (pd.warning === "low_battery" || pd.warning === "critical_battery") {
                    root.enqueueActivity("battery-warning","Battery: "+Math.round(pd.percentage||0)+"%","\uF244",1,1,root.priorityBatteryWarning,8000);
                }
                return;
            }
        }
    }

    // Model watchers (direct fallback when daemon events are slow)
    Connections {
        target: audio
        function onOutputVolumeChanged() {
            if (!audio.available || Date.now() < root.cooldownUntil) return;
            if (Math.abs(audio.outputVolume - guardVolume) <= 1) return;
            guardVolume = audio.outputVolume;
            root.enqueueActivity("volume","Volume","\uF028",audio.outputVolume,audio.maxVolume||100,root.priorityVolume,2000);
        }
    }
    Connections {
        target: brightness
        function onPercentageChanged() {
            if (!brightness.available || Date.now() < root.cooldownUntil) return;
            if (Math.abs(brightness.percentage - guardBrightness) <= 1) return;
            guardBrightness = brightness.percentage;
            root.enqueueActivity("brightness","Brightness","\uF185",brightness.percentage,100,root.priorityBrightness,2000);
        }
    }

    // ── Hide timer ──
    property Timer hideTimer: Timer {
        interval: 2000; repeat: false;
        onTriggered: root.deactivate()
    }

    // ── Slider commit ──
    Timer { id: sliderCommitTimer; interval: 80; repeat: false; onTriggered: {
        if (root.sliderTarget < 0) return;
        var c = Math.max(0, Math.min(1, root.sliderTarget));
        if (islandState==="volume"&&root.noxd&&root.noxd.connected)
            root.noxd.runAction({ audio_set_volume: { target:"output", volume:Math.round(c*100) } });
        else if (islandState==="brightness"&&root.noxd&&root.noxd.connected)
            root.noxd.runAction({ brightness_set: { percentage:Math.round(c*root.activityMaximum) } });
    }}
    function commitSlider(v) { root.sliderTarget = v; sliderCommitTimer.restart(); }

    // ── UI ──
    Rectangle {
        anchors.fill: parent
        radius: expanded ? Theme.Tokens.radiusXl : Theme.Tokens.radiusPill
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1

        Behavior on radius {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
        }

        Item {
            anchors.fill: parent
            anchors.margins: expanded ? Theme.Tokens.spacingLg : Theme.Tokens.spacingSm
            clip: true

            RowLayout {
                anchors.fill: parent
                spacing: expanded ? Theme.Tokens.spacingMd : Theme.Tokens.spacingSm

                // Icon
                Text {
                    text: root.activityIcon
                    color: Theme.Tokens.tonalPrimary
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: expanded ? Theme.Tokens.iconLg : Theme.Tokens.iconSm
                    Layout.alignment: Qt.AlignVCenter
                }

                // Label + progress column
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: expanded ? Theme.Tokens.scaled(Theme.Tokens.spacingXs) : 0

                    Text {
                        text: root.activityLabel
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: expanded ? Theme.Tokens.typographyLabelLarge : Theme.Tokens.typographyBodySmall
                        font.bold: expanded
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Detail text (expanded only)
                    Text {
                        visible: expanded && root.activityDetail !== "" && !(root.activityMaximum > 1)
                        text: root.activityDetail
                        color: Theme.Tokens.textSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Progress bar (only when maximum > 1 and value >= 0)
                    Rectangle {
                        Layout.fillWidth: true
                        height: expanded ? 5 : 3
                        radius: 2
                        color: Theme.Tokens.outlineSubtle
                        visible: root.activityMaximum > 1 && root.activityValue >= 0

                        Rectangle {
                            width: parent.width * Math.min(1, root.activityValue / root.activityMaximum)
                            height: parent.height
                            radius: parent.radius
                            color: islandState === "brightness" ? Theme.Tokens.stateWarning
                                 : islandState === "battery-warning" ? Theme.Tokens.stateDanger
                                 : Theme.Tokens.tonalPrimary

                            Behavior on width {
                                enabled: !root.reducedMotion
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                // Value percentage (compact only)
                Text {
                    visible: !expanded && root.activityMaximum > 1
                    text: root.displayPercent + "%"
                    color: Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // ── Timer helpers (callable from IPC/launcher) ──
    function formatTime(s) {
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
    function startTimer(s) {
        if (s <= 0) return;
        timerTotalSeconds = s;
        timerRemainingSeconds = s;
        timerActive = true;
        enqueueActivity("timer", "Timer " + formatTime(s), "\uF017", 1, 1, priorityTimer, 120000);
    }
    function showRecording() {
        enqueueActivity("recording", "Recording", "\uF111", 0, 1, priorityRecording, 30000);
    }
    function stopRecording() {
        if (islandState === "recording") deactivate();
    }
    function showNotification(s, b) {
        enqueueActivity("notification", s || "Notification", "\uF0F3", 0, 1, priorityNotification, 5000);
    }

    // ── Additional activity triggers (for external callers) ──
    function showFileTransfer(name, progress) {
        fileTransferName = name || "";
        fileTransferProgress = progress || 0;
        fileTransferActive = true;
        enqueueActivity("file-transfer", name || "File transfer", "\uF093", progress, 1, priorityFileTransfer, 8000);
    }
    function showAiCompletion(text) {
        aiCompletionText = text || "";
        enqueueActivity("ai-completion", text ? "AI: " + text : "AI completion", "\uF0C3", 0, 1, priorityAiCompletion, 6000);
    }
    function showBuildResult(text, success) {
        buildResultText = text || "";
        buildResultStatus = success ? 1 : 2;
        enqueueActivity("build-result", text || (success ? "Build succeeded" : "Build failed"),
            success ? "\uF00C" : "\uF00D", 0, 1, priorityBuildResult, 10000);
    }
    function showBatteryWarning(percent) {
        enqueueActivity("battery-warning", "Battery: " + Math.round(percent) + "%", "\uF244",
            1, 1, priorityBatteryWarning, 8000);
    }
    function showNetworkWarning(message) {
        enqueueActivity("network-warning", message || "Network issue", "\uF1EB",
            1, 1, priorityNetworkWarning, 6000);
    }
}
