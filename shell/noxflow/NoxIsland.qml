// Nox Island — contextual live-activity pill/card. Centered, right below the top bar.
// Appears for: volume, brightness, media, notifications, timers, mic, recording, file transfer,
// AI completion, build results, battery/network warnings. Hides automatically.
// To use: change volume/brightness, play media, start timer, receive notification, call show*().

import QtQuick; import QtQuick.Layouts; import Quickshell; import Quickshell.Wayland
import "theme" as Theme

Item {
    id: root
    property var screen
    required property var noxd; required property var audio; required property var brightness

    readonly property var states: ["idle","volume","brightness","media","mic","recording","timer","notification","output-mute","input-mute","file-transfer","ai-completion","build-result","battery-warning","network-warning"]
    property string islandState: "idle"; property bool rendered: true; property bool expanded: false
    property bool idleHovered: false
    property bool hoverExpanded: false
    property bool pointerInside: false
    readonly property bool visualExpanded: expanded || hoverExpanded
    property date now: new Date()
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    property string activityLabel: ""; property string activityIcon: ""; property real activityValue: 0; property real activityMaximum: 100
    property string activityDetail: ""
    property string mediaTitle: ""; property string mediaArtist: ""; property string mediaArtwork: ""; property string mediaStatus: ""; property bool mediaAvailable: false
    property int timerTotalSeconds: 0; property int timerRemainingSeconds: 0; property bool timerActive: false
    property string fileTransferName: ""; property real fileTransferProgress: 0; property bool fileTransferActive: false
    property string aiCompletionText: ""; property string buildResultText: ""; property int buildResultStatus: 0
    property int displayPercent: Math.round(activityMaximum > 0 ? (activityValue/activityMaximum*100) : activityValue)
    property int lastOutputVolume: audio.outputVolume; property bool lastOutputMuted: audio.outputMuted; property bool lastInputMuted: audio.inputMuted
    property real guardVolume: -1; property real guardBrightness: -1
    // Provider snapshots arrive asynchronously during shell startup. Ignore
    // all OSD-worthy changes until both baselines are captured; otherwise a
    // restart is incorrectly shown as a user brightness/volume adjustment.
    property bool suppressStartupEvents: true
    // Guards are seeded only after the first real daemon snapshot. The initial
    // snapshot must never trigger the OSD (login volume/brightness flash bug).
    property bool guardsSeeded: false

    // Seed volume/brightness guards from the synced model values. Called on the
    // first snapshot application (via Connections to hasSynced), and again on
    // Component.onCompleted for the already-synced case.
    function seedGuards() {
        if (!guardsSeeded && audio.hasSynced) guardVolume = audio.outputVolume;
        if (!guardsSeeded && brightness.hasSynced) guardBrightness = brightness.percentage;
        if (guardsSeeded || (audio.hasSynced && brightness.hasSynced)) guardsSeeded = true;
    }

    // Priority queue
    property var queue: []
    property string currentKind: "idle"; property int currentPriority: 0; property double currentStarted: 0
    property var lastEventKeys: ({})

    readonly property int priTimer: 9; readonly property int priRecording: 9; readonly property int priNotification: 8
    readonly property int priAiCompletion: 7; readonly property int priBuildResult: 7; readonly property int priFileTransfer: 6
    readonly property int priMedia: 5; readonly property int priBattery: 8; readonly property int priNetwork: 8
    readonly property int priVolume: 3; readonly property int priBrightness: 3; readonly property int priOutputMute: 4; readonly property int priInputMute: 4

    // Transparent layer-shell host. The island is the only opaque object in
    // this layer; the top bar underneath remains fully transparent.
    visible: rendered
    implicitHeight: visualExpanded ? Theme.Tokens.scaled(76) : Theme.Tokens.scaled(38)

    readonly property real pillW: Theme.Tokens.scaled(190)
    readonly property real expandW: screen ? Math.min(screen.width * 0.42, Theme.Tokens.scaled(450)) : Theme.Tokens.scaled(450)

    Behavior on implicitHeight { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

    Component.onCompleted: { rendered = true; islandState = "idle"; currentKind = "idle"; root.seedGuards(); }

    // Queue
    function enqueue(kind, label, icon, value, maximum, priority, timeout) {
        var key = kind + "::" + label; var now = Date.now();
        if (lastEventKeys[key] && (now - lastEventKeys[key]) < 300) return; lastEventKeys[key] = now;
        queue = queue.filter(function(e) { return e.kind !== kind; });
        queue.unshift({ kind:kind, label:label, icon:icon, value:value, maximum:maximum, priority:priority, timeout:timeout, timestamp:now });
        queue.sort(function(a,b) { return b.priority - a.priority; });
        processQueue();
    }
    function processQueue() {
        if (queue.length === 0) { if (currentKind !== "idle") { hideTimer.interval = 500; hideTimer.restart(); } return; }
        var top = queue[0];
        if (top.priority < currentPriority && top.kind !== currentKind && currentKind !== "idle") return;
        queue.shift();
        display(top);
    }
    function shouldExpand(kind) { return ["media","notification","timer","file-transfer","ai-completion","build-result","recording"].indexOf(kind) >= 0; }
    function display(entry) { currentKind = entry.kind; currentPriority = entry.priority; currentStarted = Date.now(); islandState = entry.kind; activityLabel = entry.label; activityIcon = entry.icon; activityValue = Math.max(0,entry.value); activityMaximum = Math.max(1,entry.maximum); expanded = shouldExpand(entry.kind); rendered = true; hideTimer.stop(); hideTimer.interval = entry.timeout; hideTimer.restart(); }
    function deactivate() { rendered = true; expanded = false; islandState = "idle"; currentKind = "idle"; currentPriority = 0; currentStarted = 0; root.seedGuards(); processQueue(); }

    // Events
    Connections { target: noxd
        function onEventReceived(e) { if (!e || !e.provider) return;
            if (e.provider === "audio" && e.data) {
                var v = Number(e.data.output_volume); if (isFinite(v)) { lastOutputVolume = v; lastOutputMuted = e.data.output_muted === true; lastInputMuted = e.data.input_muted === true; }
                if (!audio.hasSynced || root.suppressStartupEvents || root.guardVolume < 0) { root.seedGuards(); return; } // initial snapshot — never display
                if (isFinite(v) && Math.abs(v - guardVolume) > 1) { guardVolume = v; root.enqueue("volume","Volume","\uF028",v,100,root.priVolume,2000); }
                else if (e.data.output_muted !== undefined && e.data.output_muted !== lastOutputMuted) { root.enqueue("output-mute",e.data.output_muted?"Muted":"Unmuted",e.data.output_muted?"\uF026":"\uF028",v||0,100,root.priOutputMute,2000); }
                else if (e.data.input_muted !== undefined && e.data.input_muted !== lastInputMuted) { root.enqueue("input-mute",e.data.input_muted?"Mic Muted":"Mic Live","\uF130",0,1,root.priInputMute,2000); } return; }
            if (e.provider === "brightness" && e.data) {
                var b = Number(e.data.percentage); if (!brightness.hasSynced || root.suppressStartupEvents || root.guardBrightness < 0) { root.seedGuards(); return; } if (isFinite(b) && Math.abs(b - guardBrightness) > 1) { guardBrightness = b; root.enqueue("brightness","Brightness","\uF185",b,100,root.priBrightness,2000); } return; }
            if (e.provider === "media") { var md = e.data || {}; if (md.playback_status === "playing" || md.title) { mediaTitle = md.title||""; mediaArtist = md.artists?(Array.isArray(md.artists)?md.artists.join(", "):String(md.artists)):""; mediaArtwork = md.artwork_url||md.artwork_cache||""; mediaStatus = md.playback_status||""; mediaAvailable = true; root.enqueue("media",mediaTitle,"\uF001",50,100,root.priMedia,5000); } else { mediaAvailable = false; } return; }
            if (e.provider === "notifications") { var nd = e.data||{}; root.enqueue("notification",nd.summary||nd.app_name||"Notification","\uF0F3",1,1,root.priNotification,5000); return; }
            if (e.provider === "power") { var pd = e.data||{}; if (pd.warning === "low_battery"||pd.warning==="critical_battery") root.enqueue("battery-warning","Battery: "+Math.round(pd.percentage||0)+"%","\uF244",1,1,root.priBattery,8000); return; }
        }
    }
    Connections { target: audio; function onOutputVolumeChanged() { root.seedGuards(); if (!audio.hasSynced || root.suppressStartupEvents || root.guardVolume < 0) return; if (Math.abs(audio.outputVolume - guardVolume) <= 1) return; guardVolume = audio.outputVolume; root.enqueue("volume","Volume","\uF028",audio.outputVolume,audio.maxVolume||100,root.priVolume,2000); } }
    Connections { target: brightness; function onPercentageChanged() { root.seedGuards(); if (!brightness.hasSynced || root.suppressStartupEvents || root.guardBrightness < 0) return; if (Math.abs(brightness.percentage - guardBrightness) <= 1) return; guardBrightness = brightness.percentage; root.enqueue("brightness","Brightness","\uF185",brightness.percentage,100,root.priBrightness,2000); } }

    // Re-seed guards the moment each provider delivers its first synced value,
    // in case the island component completes before the daemon snapshot.
    Connections { target: audio; function onHasSyncedChanged() { root.seedGuards(); } }
    Connections { target: brightness; function onHasSyncedChanged() { root.seedGuards(); } }

    Timer { id: hideTimer; interval: 2000; repeat: false; onTriggered: root.deactivate() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.now = new Date() }
    Timer { id: startupGuardTimer; interval: 5000; repeat: false; running: true; onTriggered: { root.seedGuards(); root.suppressStartupEvents = false; } }
    Timer { id: hoverOpenTimer; interval: 180; repeat: false; onTriggered: { if (root.pointerInside && root.islandState === "idle") root.hoverExpanded = true; } }
    Timer { id: hoverCloseTimer; interval: 300; repeat: false; onTriggered: { if (!root.pointerInside) root.hoverExpanded = false; } }

    // Centered pill/card
    Rectangle {
        id: islandCard
        anchors.centerIn: parent
        width: root.visualExpanded ? root.expandW : root.pillW; height: parent.height
        radius: root.visualExpanded ? Theme.Tokens.radiusXl : Theme.Tokens.radiusPill
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, Theme.Tokens.glassPanelAlpha)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
        Behavior on radius { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

        RowLayout { anchors.fill: parent; anchors.margins: root.visualExpanded ? Theme.Tokens.spacingLg : Theme.Tokens.spacingSm; spacing: root.visualExpanded ? Theme.Tokens.spacingMd : Theme.Tokens.spacingSm
            Text { text: root.islandState === "idle" ? "\uF017" : root.activityIcon; color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: root.visualExpanded ? Theme.Tokens.iconLg : Theme.Tokens.iconSm; Layout.alignment: Qt.AlignVCenter }
            ColumnLayout { Layout.fillWidth: true; spacing: root.visualExpanded ? Theme.Tokens.scaled(Theme.Tokens.spacingXs) : 0
                Text { text: root.islandState === "idle" ? Qt.formatTime(root.now, "HH:mm") : root.activityLabel; color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: root.islandState === "idle" ? Theme.Tokens.typographyTitleMedium : root.visualExpanded ? Theme.Tokens.typographyLabelLarge : Theme.Tokens.typographyBodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                Text { visible: root.islandState === "idle" && root.hoverExpanded; text: Qt.formatDate(root.now, "ddd, d MMM") + "  ·  Open calendar"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                Rectangle { Layout.fillWidth: true; height: root.visualExpanded ? 5 : 3; radius: 2; color: Theme.Tokens.outlineSubtle; visible: root.activityMaximum > 1 && root.activityValue >= 0
                    Rectangle { width: parent.width * Math.min(1,root.activityValue/root.activityMaximum); height: parent.height; radius: parent.radius; color: root.islandState === "brightness" ? Theme.Tokens.stateWarning : root.islandState === "battery-warning" ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                        Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } } }
            }
            Text { visible: !root.visualExpanded && root.islandState !== "idle" && root.activityMaximum > 1; text: root.displayPercent + "%"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.alignment: Qt.AlignVCenter }
        }
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                root.pointerInside = hovered
                root.idleHovered = hovered
                if (hovered) {
                    hoverCloseTimer.stop()
                    if (root.islandState === "idle") hoverOpenTimer.restart()
                } else {
                    hoverOpenTimer.stop()
                    hoverCloseTimer.restart()
                }
            }
        }
        TapHandler { onTapped: if (root.islandState === "idle") shellRoot.coordinator.toggle("calendar", root.screen && root.screen.name ? root.screen.name : "", root.islandGeometry()) }
    }

    function islandGeometry() {
        var p = islandCard.mapToItem(null, 0, 0)
        return Qt.rect(p.x, p.y, islandCard.width, islandCard.height)
    }

    // Public helpers
    function formatTime(s) { var m = Math.floor(s/60); var r = s%60; return m+":"+(r<10?"0":"")+r; }
    function startTimer(s) { if (s <= 0) return; timerTotalSeconds = s; timerRemainingSeconds = s; timerActive = true; enqueue("timer","Timer "+formatTime(s),"\uF017",1,1,priTimer,120000); }
    function showRecording() { enqueue("recording","Recording","\uF111",0,1,priRecording,30000); }
    function stopRecording() { if (islandState === "recording") deactivate(); }
    function showNotification(s,b) { enqueue("notification",s||"Notification","\uF0F3",0,1,priNotification,5000); }
    function showFileTransfer(name,progress) { fileTransferName = name||""; fileTransferProgress = progress||0; fileTransferActive = true; enqueue("file-transfer",name||"File transfer","\uF093",progress,1,priFileTransfer,8000); }
    function showAiCompletion(text) { aiCompletionText = text||""; enqueue("ai-completion",text?"AI: "+text:"AI completion","\uF0C3",0,1,priAiCompletion,6000); }
    function showBuildResult(text,success) { buildResultText = text||""; buildResultStatus = success?1:2; enqueue("build-result",text||(success?"Build succeeded":"Build failed"),success?"\uF00C":"\uF00D",0,1,priBuildResult,10000); }
    function showBatteryWarning(pct) { enqueue("battery-warning","Battery: "+Math.round(pct)+"%","\uF244",1,1,priBattery,8000); }
    function showNetworkWarning(msg) { enqueue("network-warning",msg||"Network issue","\uF1EB",1,1,priNetwork,6000); }
}
