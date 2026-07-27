// Nox Island — morphing live-activity surface.
// Rebuilt with Tide Island's state-machine pattern + priority queue.
// States: idle, volume, brightness, media, mic, recording, timer, notification, output-mute, input-mute
// Priority: notification > recording > mic > timer > media > volume/brightness
// Auto-hides with edge-gesture reveal, hover-expand, content cross-fade.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "theme" as Theme
import "components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var audio
    required property var brightness

    // ── State machine ──
    readonly property var validStates: ["idle", "volume", "brightness", "media", "mic", "recording", "timer", "notification", "output-mute", "input-mute"]
    property string islandState: "idle"
    onIslandStateChanged: {
        if (validStates.indexOf(islandState) < 0) {
            console.error("NoxIsland: invalid state '" + islandState + "' — reverting to idle");
            islandState = "idle";
        }
    }
    property bool rendered: false
    property bool expanded: true
    property bool autoHideEnabled: true
    property bool autoHideForcedHidden: false
    property bool reducedMotion: Theme.Tokens.reducedMotion

    // ── Tide-style priority queue ──
    property var stateQueue: []         // Array of {kind, label, icon, value, max, duration}
    property string restingState: "idle"
    property var priorityMap: ({
        notification: 10,
        recording: 9,
        mic: 8,
        timer: 7,
        media: 6,
        volume: 5,
        brightness: 5,
        "output-mute": 4,
        "input-mute": 3,
        idle: 0,
    })
    function statePriority(kind) { return priorityMap[kind] || 0; }

    // ── Hover-expand (Tide pattern) ──
    property bool hoverExpandEnabled: true
    property bool hovered: false
    property bool autoExpanded: false     // was expanded by hover?
    onHoveredChanged: {
        if (hoverExpandEnabled && hovered && !expanded) {
            expanded = true;
            autoExpanded = true;
            compactTimer.stop();
        } else if (autoExpanded && !hovered && !compactTimer.running) {
            compactTimer.restart();
        }
    }

    // Activity data
    property string activityLabel: ""
    property string activityIcon: ""
    property real activityValue: 0
    property real activityMaximum: 100

    // Media
    property var mediaTitle: ""
    property var mediaArtist: ""
    property var mediaArtwork: ""
    property var mediaStatus: ""
    property bool mediaAvailable: false

    // Timer
    property int timerTotalSeconds: 0
    property int timerRemainingSeconds: 0
    property bool timerActive: false

    // Tracking
    property int lastOutputVolume: audio.outputVolume
    property bool lastOutputMuted: audio.outputMuted
    property bool lastInputMuted: audio.inputMuted

    // ── Window setup (centred top, overlay layer) ──
    screen: root.screen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: Theme.Tokens.scaled(4)  // small gap from screen edge
    exclusiveZone: 0
    aboveWindows: true
    focusable: false
    color: "transparent"
    visible: rendered && !autoHideForcedHidden
    property bool showStartup: true
    Component.onCompleted: {
        if (showStartup) {
            // Show idle state permanently — timeout 0 means stay until overridden
            root.show("idle", "NoxFlow", "⊚", 0, 1, 0, 0);
            showStartup = false;
        }
    }

    // Edge gesture reveal strip — transparent but catches mouse at top edge
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: Theme.Tokens.scaled(400)
        height: autoHideForcedHidden ? Theme.Tokens.scaled(4) : 0
        z: 100
        HoverHandler {
            onHoveredChanged: {
                if (hovered && root.autoHideForcedHidden) {
                    root.autoHideForcedHidden = false;
                }
            }
        }
    }

    implicitWidth: expanded ? Theme.Tokens.scaled(400) : Theme.Tokens.scaled(240)
    implicitHeight: {
        switch (islandState) {
            case "media": return mediaAvailable && expanded ? Theme.Tokens.scaled(180) : Theme.Tokens.scaled(76)
            case "timer": return timerActive && expanded ? Theme.Tokens.scaled(120) : Theme.Tokens.scaled(76)
            default: return Theme.Tokens.scaled(76)
        }
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.Tokens.duration(250); easing.type: Easing.InOutCubic }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.Tokens.duration(250); easing.type: Easing.InOutCubic }
    }

    // ── Event handling ──
    Connections {
        target: noxd
        function onEventReceived(event) { root.handleEvent(event) }
    }

    // ── Direct model watchers (for keyboard/OS changes that bypass noxd) ──
    property real lastWatchVolume: -1
    property real lastWatchBrightness: -1

    Connections {
        target: audio
        function onOutputVolumeChanged() {
            if (!audio.available) return;
            if (root.lastWatchVolume < 0) { root.lastWatchVolume = audio.outputVolume; return; }
            if (audio.outputVolume !== root.lastWatchVolume) {
                root.lastWatchVolume = audio.outputVolume;
                root.show("volume", "Volume", "◉", audio.outputVolume, audio.maxVolume || 100, 5, 2000);
            }
        }
        function onOutputMutedChanged() {
            root.show("output-mute", audio.outputMuted ? "Muted" : "Unmuted",
                     audio.outputMuted ? "⊘" : "◉", audio.outputVolume, audio.maxVolume || 100, 4, 2000);
        }
    }

    Connections {
        target: brightness
        function onPercentageChanged() {
            if (!brightness.available) return;
            if (root.lastWatchBrightness < 0) { root.lastWatchBrightness = brightness.percentage; return; }
            if (brightness.percentage !== root.lastWatchBrightness) {
                root.lastWatchBrightness = brightness.percentage;
                root.show("brightness", "Brightness", "☼", brightness.percentage, 100, 5, 2000);
            }
        }
    }

    // ── Timers ──
    Timer {
        id: compactTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.expanded = false;
            root.autoExpanded = false;
        }
    }

    Timer {
        id: hideTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (root.stateQueue.length > 0) {
                root.dequeueNext();
            } else {
                root.deactivate();
            }
        }
    }

    Timer {
        id: restStateTimer
        interval: 150     // ms to wait before restoring resting state after transient
        repeat: false
        onTriggered: root.restoreRestingState()
    }

    Timer {
        id: timerTick
        interval: 1000
        repeat: true
        running: root.timerActive
        onTriggered: {
            root.timerRemainingSeconds -= 1
            if (root.timerRemainingSeconds <= 0) {
                root.timerActive = false
                root.show("timer", "Timer finished", "⏰", 0, 1, 10, 5000)
            }
        }
    }

    // ── Animations ──
    // Deactivate timer (replaces opacity-based exitAnimation — PanelWindow doesn't support opacity animation)
    Timer {
        id: deactivateTimer
        interval: Theme.Tokens.duration(180)
        repeat: false
        onTriggered: root.rendered = false
    }

    SequentialAnimation {
        id: contentAnimation
        NumberAnimation { target: root; property: "contentOpacity"; to: 0; duration: Theme.Tokens.duration(80); easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "contentOpacity"; to: 1; duration: Theme.Tokens.duration(120); easing.type: Easing.OutCubic }
    }

    property real contentOpacity: 1

    // ── Vertical slider state (volume/brightness) ──
    property bool sliderDragging: false
    property real sliderTarget: -1      // debounced target value
    property real sliderCommitThreshold: 0.02

    Timer {
        id: sliderCommitTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.sliderTarget < 0) return;
            var clamped = Math.max(0, Math.min(1, root.sliderTarget));
            if (islandState === "volume") {
                if (root.noxd && root.noxd.connected) {
                    root.noxd.runAction({ volume_set: { value: clamped * root.activityMaximum } });
                }
            } else if (islandState === "brightness") {
                if (root.noxd && root.noxd.connected) {
                    root.noxd.runAction({ brightness_set: { value: clamped * root.activityMaximum } });
                }
            }
        }
    }

    function commitSlider(value) {
        root.sliderTarget = value;
        sliderCommitTimer.restart();
    }

    function clamp01(v) { return Math.max(0, Math.min(1, v)); }

    // ── Core functions ──
    function deactivate() {
        if (reducedMotion) rendered = false
        else deactivateTimer.restart()
    }

    // Priority-aware show: higher-priority events interrupt, lower-priority queue
    function show(kind, label, icon, value, maximum, priority, timeout) {
        if (priority === undefined) priority = root.priorityMap[kind] || 0;
        if (timeout === undefined) timeout = 4000;

        var isHigher = priority > root.statePriority(root.islandState);
        var isSame = priority === root.statePriority(root.islandState) && kind !== root.islandState;

        if (!rendered || isHigher || isSame) {
            // Display now
            var previousKind = root.islandState;
            deactivateTimer.stop()
            rendered = true
            expanded = true
            autoHideForcedHidden = false
            islandState = kind
            activityLabel = label
            activityIcon = icon
            activityValue = Math.max(0, value)
            activityMaximum = Math.max(1, maximum)

            compactTimer.restart()
            // idle state stays visible forever, other states auto-hide
            if (kind === "idle") {
                hideTimer.stop();
            } else {
                hideTimer.interval = timeout > 0 ? timeout : 4000;
                hideTimer.restart();
            }
            if (previousKind !== kind && !reducedMotion) contentAnimation.restart()
            else contentOpacity = 1

            // If the previous state was a visible one and isn't idle, queue it for restore
            if (previousKind !== "idle" && previousKind !== kind) {
                root.enqueueState(previousKind);
            }
        } else {
            // Queue for later display
            root.enqueueState(kind, label, icon, value, maximum, priority, timeout);
        }
    }

    function enqueueState(kind, label, icon, value, maximum, priority, timeout) {
        // Don't queue duplicates
        for (var i = 0; i < stateQueue.length; i++) {
            if (stateQueue[i].kind === kind) return;
        }
        var q = stateQueue.concat([{
            kind: kind, label: label, icon: icon,
            value: value, max: maximum,
            priority: priority || root.priorityMap[kind] || 0,
            timeout: timeout || 4000,
        }]);
        q.sort(function(a, b) { return b.priority - a.priority; });
        stateQueue = q;  // reassign to trigger QML bindings
    }

    function dequeueNext() {
        if (stateQueue.length === 0) {
            root.restoreRestingState();
            return;
        }
        var next = stateQueue[0];
        stateQueue = stateQueue.slice(1);
        root.show(next.kind, next.label, next.icon, next.value, next.max, next.priority, next.timeout);
    }

    function restoreRestingState() {
        if (stateQueue.length > 0) {
            dequeueNext();
        } else if (restingState !== "idle" && restingState !== root.islandState) {
            root.show(restingState, "", "", 0, 1, 0, 4000);
        } else {
            root.deactivate();
        }
    }

    function handleEvent(event) {
        if (!event || typeof event !== "object") return

        // Brightness
        if (event.provider === "brightness" && event.event_type === "brightness_changed") {
            var briValue = Number(event.data.percentage)
            if (isFinite(briValue)) show("brightness", "Brightness", "☼", briValue, 100, 5)
            return
        }

        // Media
        if (event.provider === "media") {
            var mediaData = event.data || {}
            if (mediaData.playback_status === "playing" || mediaData.title) {
                mediaTitle = mediaData.title || ""
                mediaArtist = mediaData.artists ? mediaData.artists.join(", ") : ""
                mediaArtwork = mediaData.artwork_url || mediaData.artwork_cache || ""
                mediaStatus = mediaData.playback_status || ""
                mediaAvailable = true
                show("media", mediaTitle, "♫", mediaData.volume !== null ? mediaData.volume * 100 : 50, 100, 6)
            } else if (mediaData.playback_status === "stopped" || !mediaData.title) {
                mediaAvailable = false
            }
            return
        }

        // Audio
        if (event.provider !== "audio" || event.event_type !== "state_changed") return
        var data = event.data || {}
        var outputVolume = Number(data.output_volume)
        var outputMuted = data.output_muted === true
        var inputMuted = data.input_muted === true
        var maxVolume = Number(audio.maxVolume) || 100

        if (isFinite(outputVolume) && outputVolume !== lastOutputVolume) {
            show("volume", "Volume", "◉", outputVolume, maxVolume, 5)
        } else if (outputMuted !== lastOutputMuted) {
            show("output-mute", outputMuted ? "Muted" : "Unmuted", outputMuted ? "⊘" : "◉", outputVolume, maxVolume, 4)
        } else if (inputMuted !== lastInputMuted) {
            show("mic", inputMuted ? "Mic muted" : "Mic active", inputMuted ? "⊗" : "◌", Number(data.input_volume) || 0, maxVolume, 8)
        }
        if (isFinite(outputVolume)) lastOutputVolume = outputVolume
        lastOutputMuted = outputMuted
        lastInputMuted = inputMuted
    }

    // ── Public API for IPC ──
    function startTimer(seconds) {
        if (seconds <= 0) return
        timerTotalSeconds = seconds
        timerRemainingSeconds = seconds
        timerActive = true
        show("timer", "Timer " + formatTime(seconds), "⏱", 1, 1, 7)
    }

    function showRecording() {
        show("recording", "Recording", "⏺", 0, 1, 9, 30000)
    }

    function stopRecording() {
        if (islandState === "recording") deactivate()
    }

    function formatTime(seconds) {
        var m = Math.floor(seconds / 60)
        var s = seconds % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function showNotification(summary, body) {
        show("notification", summary || "Notification", "◈", 0, 1, 10)
    }

    // ── UI ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        opacity: root.contentOpacity

        // Hover Area for hover-expand
        HoverHandler {
            onHoveredChanged: root.hovered = hovered
        }

        // Morphing scale entrance effect
        scale: root.rendered ? 1.0 : 0.85
        Behavior on scale {
            NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack }
        }

        // ── Content layers (swapped by state) ──
        Item {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            clip: true

            // Default: icon + label + progress
            RowLayout {
                anchors.fill: parent
                spacing: Theme.Tokens.spacingMd
                visible: islandState !== "media" || !expanded || !mediaAvailable

                Text {
                    text: root.activityIcon
                    color: Theme.Tokens.tonalPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.iconLg
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

                    Text {
                        text: islandState === "timer" && timerActive
                              ? "Timer — " + formatTime(timerRemainingSeconds)
                              : root.expanded ? root.activityLabel : root.activityLabel
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelLarge
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Progress bar (visible when activityValue is meaningful)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 5
                        radius: 3
                        color: Theme.Tokens.outlineSubtle
                        visible: root.activityMaximum > 1 && root.activityValue >= 0

                        Rectangle {
                            width: parent.width * Math.min(1, root.activityValue / root.activityMaximum)
                            height: parent.height
                            radius: parent.radius
                            color: islandState === "volume" || islandState === "output-mute"
                                   ? Theme.Tokens.tonalPrimary
                                   : islandState === "recording"
                                   ? Theme.Tokens.stateDanger
                                   : islandState === "timer" && timerRemainingSeconds <= 10
                                   ? Theme.Tokens.stateWarning
                                   : Theme.Tokens.tonalPrimary

                            Behavior on width {
                                 NumberAnimation { duration: Theme.Tokens.duration(120); easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                // Value label (percentage or countdown)
                Text {
                    text: islandState === "timer" && timerActive
                          ? formatTime(timerRemainingSeconds)
                          : Math.round(root.activityValue) + "%"
                    color: islandState === "recording" ? Theme.Tokens.stateDanger
                         : islandState === "timer" && timerRemainingSeconds <= 10 ? Theme.Tokens.stateWarning
                         : Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelLarge
                    font.bold: islandState === "recording" || islandState === "timer"
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // ── Vertical slider for volume/brightness (appears on hover when expanded) ──
            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Theme.Tokens.scaled(24)
                visible: (islandState === "volume" || islandState === "brightness")
                         && expanded && (root.hovered || root.sliderDragging)
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }

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
                        height: parent.height * Math.min(1, Math.max(0, root.activityValue / root.activityMaximum))
                        radius: parent.radius
                        color: islandState === "volume"
                               ? Theme.Tokens.tonalPrimary
                               : Theme.Tokens.stateWarning
                    }

                    // Knob
                    Rectangle {
                        x: parent.x - 6
                        y: parent.y + parent.height * (1 - Math.min(1, Math.max(0, root.activityValue / root.activityMaximum))) - 8
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
                        return root.clamp01(1 - mouseY / height);
                    }

                    onPressed: function(mouse) {
                        root.sliderDragging = true;
                        var v = valueFromMouse(mouse.y);
                        root.activityValue = v * root.activityMaximum;
                        root.commitSlider(v);
                    }
                    onPositionChanged: function(mouse) {
                        if (!root.sliderDragging) return;
                        var v = valueFromMouse(mouse.y);
                        root.activityValue = v * root.activityMaximum;
                        root.commitSlider(v);
                    }
                    onReleased: {
                        root.sliderDragging = false;
                    }
                }
            }

            // Media expanded layer (when expanded and media available)
            RowLayout {
                anchors.fill: parent
                spacing: Theme.Tokens.spacingMd
                visible: islandState === "media" && expanded && mediaAvailable

                // Album art
                Rectangle {
                    width: Theme.Tokens.scaled(56)
                    height: Theme.Tokens.scaled(56)
                    radius: Theme.Tokens.radiusMd
                    color: Theme.Tokens.surfaceSurfaceVariant
                    visible: mediaArtwork === ""

                    Text {
                        anchors.centerIn: parent
                        text: "♫"
                        color: Theme.Tokens.tonalPrimary
                        font.pixelSize: Theme.Tokens.iconLg
                    }

                    Image {
                        anchors.fill: parent
                        source: mediaArtwork
                        fillMode: Image.PreserveAspectCrop
                        visible: mediaArtwork !== ""
                        asynchronous: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingXs

                    Text {
                        text: mediaTitle || "No track"
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodyMedium
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: mediaArtist || ""
                        color: Theme.Tokens.textSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text !== ""
                    }
                }

                // Media controls
                RowLayout {
                    spacing: Theme.Tokens.spacingXs
                    Components.IconButton {
                        iconText: "◀"
                        accessibleName: "Previous track"
                        onClicked: { if (root.noxd.connected) root.noxd.runAction({ media_previous: {} }) }
                    }
                    Components.IconButton {
                        iconText: mediaStatus === "playing" ? "⏸" : "▶"
                        accessibleName: "Play/Pause"
                        onClicked: { if (root.noxd.connected) root.noxd.runAction({ media_play_pause: {} }) }
                    }
                    Components.IconButton {
                        iconText: "▶"
                        accessibleName: "Next track"
                        onClicked: { if (root.noxd.connected) root.noxd.runAction({ media_next: {} }) }
                    }
                }
            }
        }
    }
}
