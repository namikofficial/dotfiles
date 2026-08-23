// NoxIsland.qml — contextual live-activity pill/card with hover-hosted dashboards.
// Centered in the top bar. Idle shows date/time + one auto context.
// Wheel cycles contexts; middle-click returns to auto; manual mode resets after 10s.
// Source hover (workspace, health, connectivity, audio/power) can hand off to island dashboard.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "theme" as Theme
import "HoverEngagement.js" as HoverEngagement
import "surfaces/calendar" as CalendarSurface

Item {
    id: root
    property var screen
    required property var noxd
    required property var audio
    required property var brightness
    required property var hyprland
    required property var calModel
    required property var launcherComponent
    required property var battery
    required property var network
    required property var bluetooth
    required property var media
    required property var notificationModel
    required property var systemModel
    required property var transfer
    required property var syncthing
    required property var updates

    // ── State machine ──
    readonly property var states: [
        "idle","volume","brightness","media","mic","recording",
        "timer","notification","output-mute","input-mute",
        "file-transfer","ai-completion","build-result",
        "battery-warning","network-warning"
    ]

    property string islandState: "idle"
    property bool rendered: true
    property alias inputRegionItem: islandCard
    property bool expanded: false
    property bool hoverExpanded: false

    // ── Hover-and-pin state machine ──
    // Per-source hover is tracked independently so source hover, island
    // body hover, and pinned/manual state stay decoupled. See
    // HoverEngagement.js for the pure transition logic and generation
    // guards used here.
    property var engagement: HoverEngagement.newState()
    property int transitGraceMs: HoverEngagement.TRANSIT_GRACE_MS
    property var activeTransitToken: ({ generation: -1, deadline: 0 })
    property bool pointerInside: engagement.islandHovered
    property bool islandPinned: engagement.pin.active
    readonly property bool hoverEngaged: HoverEngagement.isEngaged(engagement)
    readonly property string effectiveEngagementKind: HoverEngagement.effectiveKind(engagement)

    // ── Manual context mode ──
    // When user scrolls the island or clicks a context, we lock to that
    // context and auto-return to "idle" after 10 seconds.
    property bool manualMode: false
    property string manualContext: "idle"

    // ── Panel yield ──
    property bool panelOpen: false
    property bool calendarExpanded: false
    property bool launcherOpen: false
    property bool launcherClosing: false
    property bool launcherWasVisible: false
    readonly property bool launcherVisible: launcherOpen || launcherClosing

    // ── Active window info ──
    property string activeWin: hyprland && hyprland.activeWindow && typeof hyprland.activeWindow === "object"
        ? String(hyprland.activeWindow.title || hyprland.activeWindow.class || hyprland.activeWindow.application_id || "").trim() : ""
    readonly property string activeApp: hyprland && hyprland.activeWindow ? (
        (function() {
            var raw = String(hyprland.activeWindow.application_id || hyprland.activeWindow.class || hyprland.activeWindow.appid || hyprland.activeWindow.initialClass || "").trim();
            if (!raw) return "";
            var pieces = raw.split(".");
            var label = pieces[pieces.length - 1].replace(/[-_]+/g, " ").trim();
            return label ? label.charAt(0).toUpperCase() + label.slice(1) : raw;
        })()
    ) : ""

    readonly property bool visualExpanded: expanded || hoverExpanded
    readonly property bool dashboardVisible: ["workspace", "health", "connectivity", "audio-power", "notification-preview", "updates", "sync", "provider-health"].indexOf(islandState) >= 0
    property date now: new Date()
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    // ── Activity state ──
    property string activityLabel: ""
    property string activityIcon: ""
    property real activityValue: 0
    property real activityMaximum: 100
    property string activityDetail: ""
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaArtwork: ""
    property string mediaStatus: ""
    property bool mediaAvailable: false
    property int timerTotalSeconds: 0
    property int timerRemainingSeconds: 0
    property bool timerActive: false
    property string fileTransferName: ""
    property real fileTransferProgress: 0
    property bool fileTransferActive: false
    property string aiCompletionText: ""
    property string buildResultText: ""
    property int buildResultStatus: 0
    property int displayPercent: Math.round(activityMaximum > 0 ? (activityValue / activityMaximum * 100) : activityValue)

    property int lastOutputVolume: audio.outputVolume
    property bool lastOutputMuted: audio.outputMuted
    property bool lastInputMuted: audio.inputMuted
    property real guardVolume: -1
    property real guardBrightness: -1
    property bool suppressStartupEvents: true
    property bool guardsSeeded: false

    function seedGuards() {
        if (!guardsSeeded && audio.hasSynced) guardVolume = audio.outputVolume;
        if (!guardsSeeded && brightness.hasSynced) guardBrightness = brightness.percentage;
        if (guardsSeeded || (audio.hasSynced && brightness.hasSynced)) guardsSeeded = true;
    }

    // ── Priority queue ──
    property var queue: []
    property string currentKind: "idle"
    property int currentPriority: 0
    property double currentStarted: 0
    property var lastEventKeys: ({})

    readonly property int priTimer: 9
    readonly property int priRecording: 9
    readonly property int priNotification: 8
    readonly property int priAiCompletion: 7
    readonly property int priBuildResult: 7
    readonly property int priFileTransfer: 6
    readonly property int priMedia: 5
    readonly property int priBattery: 8
    readonly property int priNetwork: 8
    readonly property int priVolume: 3
    readonly property int priBrightness: 3
    readonly property int priOutputMute: 4
    readonly property int priInputMute: 4

    // ── Context priority list for manual cycling ──
    // Order determines which context wins in auto mode.
    readonly property var contextPriorityList: ["focused-app", "updates", "network", "battery", "clock"]

    // ── Geometry ──
    implicitHeight: launcherVisible ? Theme.Tokens.scaled(520)
        : calendarExpanded ? Theme.Tokens.scaled(650)
        : dashboardVisible ? Theme.Tokens.scaled(226)
        : visualExpanded ? Theme.Tokens.scaled(76)
        : Theme.Tokens.scaled(38)

    readonly property real pillW: Theme.Tokens.scaled(150)
    readonly property real expandW: screen ? Math.min(screen.width * 0.42, Theme.Tokens.scaled(450)) : Theme.Tokens.scaled(450)

    Behavior on implicitHeight { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

    focus: launcherVisible || islandPinned || root.engagement.critical.active || root.engagement.osd.active || root.calendarExpanded || root.hoverEngaged
    activeFocusOnTab: launcherVisible || islandPinned
    Keys.onEscapePressed: function(event) {
        if (root.launcherVisible) { root.closeLauncher(); event.accepted = true; return; }
        if (root.calendarExpanded) { root.calendarExpanded = false; inlineCalendar.close(); event.accepted = true; return; }
        if (root.islandPinned) { root.pinRelease(); event.accepted = true; return; }
        if (root.engagement.critical.active) { return; }
        if (root.hoverEngaged) {
            // Engagement is transient — release the hover-driven source so
            // the island goes idle, but don't disturb routine OSD.
            engagement = HoverEngagement.clearSourceHover(engagement);
            root.activeTransitToken = { generation: engagement.generation, deadline: 0 };
            pointerGraceTimer.stop();
            root.maybeRetireAfterPinRelease();
            event.accepted = true;
            return;
        }
        if (root.panelOpen) {
            var coord = shellRoot.coordinator;
            if (coord && coord.activePanel) coord.close(coord.activePanel);
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        rendered = true;
        islandState = "idle";
        currentKind = "idle";
        root.seedGuards();
    }

    // ── Queue ──
    function enqueue(kind, label, icon, value, maximum, priority, timeout) {
        var key = kind + "::" + label;
        var now = Date.now();
        if (lastEventKeys[key] && (now - lastEventKeys[key]) < 300) return;
        lastEventKeys[key] = now;
        queue = queue.filter(function(e) { return e.kind !== kind; });
        queue.unshift({ kind: kind, label: label, icon: icon, value: value, maximum: maximum, priority: priority, timeout: timeout, timestamp: now });
        queue.sort(function(a, b) { return b.priority - a.priority; });
        // Critical interruptions (battery-warning, network-warning, recording,
        // timer) temporarily replace any pin and remember it for restore.
        // Routine OSD (volume, brightness, mute, …) only updates the
        // transient osd slot and never disturbs the pin.
        if (HoverEngagement.CRITICAL_KINDS.indexOf(kind) >= 0) {
            engagement = HoverEngagement.enterCritical(engagement, kind);
        } else if (HoverEngagement.OSD_KINDS.indexOf(kind) >= 0) {
            engagement = HoverEngagement.enterOsd(engagement, kind, timeout);
        }
        processQueue();
    }

    function processQueue() {
        if (queue.length === 0) {
            if (currentKind !== "idle") { hideTimer.interval = 500; hideTimer.restart(); }
            return;
        }
        var top = queue[0];
        if (top.priority < currentPriority && top.kind !== currentKind && currentKind !== "idle") return;
        queue.shift();
        display(top);
    }

    function shouldExpand(kind) {
        return ["media", "notification", "timer", "file-transfer", "ai-completion", "build-result", "recording"].indexOf(kind) >= 0;
    }

    function display(entry) {
        if (root.panelOpen) return;
        currentKind = entry.kind;
        currentPriority = entry.priority;
        currentStarted = Date.now();
        islandState = entry.kind;
        activityLabel = entry.label;
        activityIcon = entry.icon;
        activityValue = Math.max(0, entry.value);
        activityMaximum = Math.max(1, entry.maximum);
        expanded = shouldExpand(entry.kind);
        rendered = true;
        hideTimer.stop();
        hideTimer.interval = entry.timeout;
        hideTimer.restart();
    }

    function deactivate() {
        rendered = true;
        expanded = false;
        currentKind = "idle";
        currentPriority = 0;
        currentStarted = 0;
        // Clear any OSD/critical engagement so the island can re-engage from
        // a clean baseline. Pin/critical restore happens via HoverEngagement.
        if (engagement.critical.active) {
            engagement = HoverEngagement.exitCritical(engagement);
        }
        if (engagement.osd.active) {
            engagement = HoverEngagement.exitOsd(engagement);
        }
        root.restoreEngagementContext();
        root.seedGuards();
        processQueue();
    }

    function restoreEngagementContext() {
        var restored = HoverEngagement.effectiveKind(engagement);
        if (restored !== "") {
            islandState = restored;
            hoverExpanded = true;
            return;
        }
        islandState = "idle";
        hoverExpanded = false;
    }

    // ── Manual context mode ──
    // Users scrolls wheel on island -> lock to that context for 10s -> auto-return.
    property int manualModeTimeout: 10000

    function cycleContextUp() {
        if (root.islandState === "idle" || root.manualMode) {
            var list = contextPriorityList;
            var current = manualMode ? manualContext : "clock";
            var idx = list.indexOf(current);
            var next = list[(idx - 1 + list.length) % list.length];
            enterManualMode(next);
        }
    }

    function cycleContextDown() {
        if (root.islandState === "idle" || root.manualMode) {
            var list = contextPriorityList;
            var current = manualMode ? manualContext : "clock";
            var idx = list.indexOf(current);
            var next = list[(idx + 1) % list.length];
            enterManualMode(next);
        }
    }

    function enterManualMode(context) {
        manualMode = true;
        manualContext = context;
        manualModeTimer.restart();
        // Show the selected context inline
        if (context !== "clock") {
            islandState = context;
        } else {
            islandState = "idle";
        }
    }

    function exitManualMode() {
        manualMode = false;
        manualContext = "idle";
        manualModeTimer.stop();
        islandState = "idle";
    }

    Timer {
        id: manualModeTimer
        interval: manualModeTimeout
        repeat: false
        onTriggered: exitManualMode()
    }

    // ── Auto context: highest-priority available context for idle display ──
    function autoContext() {
        // Priority order: recording > timer > notification > media > focused-app > updates > network > battery > clock
        // Check in priority order which is actually "active"
        // For now, detect from existing state:
        if (currentKind !== "idle" && currentKind !== "clock") return currentKind;
        if (activeApp !== "" && hyprland && hyprland.activeWindow) return "focused-app";
        return "clock";
    }

    // ── Panel routing ──
    function openPanelForState() {
        var target = root.panelForIslandState();
        if (!target || !target.panel) return null;
        return target.panel;
    }

    function openButtonAccessibleName() {
        var panel = root.openPanelForState();
        if (!panel) return "No panel available";
        var label = panel.charAt(0).toUpperCase() + panel.slice(1).replace(/-/g, " ");
        return "Open " + label + " panel";
    }

    function panelForIslandState() {
        switch (root.islandState) {
            case "media":          return { panel: "media", section: "" };
            case "notification":   return { panel: "notifications", section: "" };
            case "file-transfer":  return { panel: "sync", section: "" };
            case "timer":          return { panel: "calendar", section: "" };
            case "volume":
            case "output-mute":
            case "input-mute":     return { panel: "quick-settings", section: "volume" };
            case "brightness":     return { panel: "quick-settings", section: "" };
            case "battery-warning": return { panel: "quick-settings", section: "battery" };
            case "network-warning": return { panel: "quick-settings", section: "network" };
            case "health":          return { panel: "quick-settings", section: "system" };
            case "connectivity":    return { panel: "quick-settings", section: "network" };
            case "audio-power":     return { panel: "quick-settings", section: "volume" };
            case "workspace":       return null;
            case "notification-preview": return { panel: "notifications", section: "" };
            case "sync":             return { panel: "sync", section: "" };
            case "provider-health":  return { panel: "quick-settings", section: "system" };
            case "network":        return { panel: "quick-settings", section: "network" };
            case "battery":        return { panel: "quick-settings", section: "battery" };
            default:               return null;
        }
    }

    function openPanelFromIsland() {
        if (root.launcherVisible) return;
        if (root.islandState === "idle") {
            root.calendarExpanded = !root.calendarExpanded;
            if (root.calendarExpanded) inlineCalendar.open();
            else inlineCalendar.close();
            return;
        }
        var target = root.panelForIslandState();
        if (target && target.panel)
            shellRoot.coordinator.toggle(target.panel, root.screen && root.screen.name ? root.screen.name : "", root.islandGeometry(), target.section);
    }

    Connections {
        target: shellRoot.coordinator
        function onActivePanelChanged() {
            var wasOpen = root.panelOpen;
            var nowOpen = shellRoot.coordinator.activePanel !== "";
            root.panelOpen = nowOpen;
            // If the major panel that was opened in tandem with the current
            // pin has now closed, retire the pin so it doesn't outlive its
            // reason for existing.
            if (wasOpen && !nowOpen) root.notifyPanelClosed(shellRoot.coordinator.previousPanel);
        }
        function onPanelChanged(panel, previous) {
            if (panel === "" && previous !== "") root.notifyPanelClosed(previous);
        }
    }

    // ── Source hover -> island engagement ──
    // Called by bar capsules when they are hovered and want to show their
    // dashboard in the island. Each source's hover state is tracked
    // independently so the user can move the pointer between chips without
    // losing the island context.
    function sourceHoverChanged(sourceKind, hovered) {
        if (HoverEngagement.SOURCE_KINDS.indexOf(sourceKind) < 0) return;
        var next = HoverEngagement.recordSourceHover(engagement, sourceKind, hovered);
        if (next === engagement) return;
        engagement = next;
        // Cancel any pending transit close: the engagement is live.
        root.activeTransitToken = { generation: engagement.generation, deadline: 0 };
        pointerGraceTimer.stop();
        if (hovered) {
            root.adoptHoveredSource(sourceKind);
        } else {
            root.armTransitTimer();
        }
    }

    function adoptHoveredSource(sourceKind) {
        if (engagement.pin.active) return;          // pin wins
        if (engagement.critical.active) return;      // critical wins
        if (manualMode) return;                      // manual context wins
        if (root.islandState === sourceKind) {
            hoverExpanded = true;
            return;
        }
        islandState = sourceKind;
        hoverExpanded = true;
        currentKind = "idle"; // suspend OSD queue while hover-driven
    }

    // Schedule a generation-guarded close timer. If hover is re-asserted
    // (source, island, pin, or critical) within the grace window, the
    // generation bump from recordSourceHover/recordIslandHover/togglePin
    // invalidates the token and the stale callback becomes a no-op.
    function armTransitTimer() {
        var token = HoverEngagement.armTransit(engagement, Date.now(), root.transitGraceMs);
        root.activeTransitToken = token;
        pointerGraceTimer.interval = root.transitGraceMs;
        pointerGraceTimer.restart();
    }

    Timer {
        id: pointerGraceTimer
        interval: root.transitGraceMs
        repeat: false
        onTriggered: {
            // Generation guard: a stale callback from a replaced engagement
            // must never close a newer one.
            if (!HoverEngagement.tickTransit(root.engagement, root.activeTransitToken, Date.now() + 1)) return;
            if (HoverEngagement.isAnyHovered(root.engagement)) return;
            if (root.engagement.pin.active) return;
            if (root.engagement.critical.active) return;
            if (root.engagement.osd.active) return;
            if (root.panelOpen) return;
            if (root.launcherVisible) return;
            // No engagement claims the island — drop it back to idle.
            if (root.islandState === "idle") {
                hoverExpanded = false;
                return;
            }
            // Routine OSD kind on top of idle queue: leave the existing
            // hideTimer to deactivate naturally.
            if (root.currentKind !== "idle") return;
            root.islandState = "idle";
            hoverExpanded = false;
        }
    }

    // ── Pin / unpin / click-away / escape ──
    // Pin the current context so the dashboard stays open until the user
    // releases it. Re-pinning the same context unpins; pinning a different
    // context swaps cleanly. Pins survive routine OSD but a critical
    // interrupt may temporarily replace one.
    function pinToggle() {
        if (root.launcherVisible) return;
        if (root.calendarExpanded) return;
        if (engagement.critical.active) return;
        var target = root.effectiveEngagementKind || root.islandState;
        if (!target || target === "idle") {
            root.calendarExpanded = true;
            inlineCalendar.open();
            return;
        }
        engagement = HoverEngagement.togglePin(engagement, target);
        root.activeTransitToken = { generation: engagement.generation, deadline: 0 };
        pointerGraceTimer.stop();
        if (engagement.pin.active) {
            islandState = engagement.pin.kind;
            hoverExpanded = true;
        } else {
            root.maybeRetireAfterPinRelease();
        }
    }

    function pinRelease() {
        if (!engagement.pin.active) return;
        engagement = HoverEngagement.releasePin(engagement);
        root.activeTransitToken = { generation: engagement.generation, deadline: 0 };
        pointerGraceTimer.stop();
        root.maybeRetireAfterPinRelease();
    }

    // Click-away is detectable inside the top-chrome input region. The
    // geometry/input-mask phase narrows that region to the bar plus card.
    function clickAwayCheck(point) {
        if (!engagement.pin.active) return;
        var cardPoint = islandCard.mapToItem(root, 0, 0);
        var islandBounds = {
            x: cardPoint.x, y: cardPoint.y,
            width: islandCard.width,
            height: islandCard.height
        };
        if (HoverEngagement.isClickAway(engagement, [], islandBounds, point)) {
            root.pinRelease();
        }
    }

    function maybeRetireAfterPinRelease() {
        // After releasing the pin, if no hover or OSD remains, fall back to
        // idle so the next user interaction starts from a clean state.
        if (HoverEngagement.isAnyHovered(engagement)) return;
        if (engagement.osd.active) return;
        if (engagement.critical.active) return;
        if (root.panelOpen) return;
        if (root.launcherVisible) return;
        root.islandState = "idle";
        hoverExpanded = false;
    }

    function notifyPanelClosed(panelName) {
        if (!engagement.pin.active) return;
        if (panelName && root.activePanelName && panelName !== root.activePanelName) return;
        root.pinRelease();
    }
    property string activePanelName: shellRoot && shellRoot.coordinator ? shellRoot.coordinator.activePanel : ""

    // ── Daemon events ──
    Connections {
        target: noxd
        function onEventReceived(e) {
            if (!e || !e.provider) return;
            if (e.provider === "audio" && e.data) {
                var v = Number(e.data.output_volume);
                var previousOutputMuted = lastOutputMuted;
                var previousInputMuted = lastInputMuted;
                if (isFinite(v)) {
                    lastOutputVolume = v;
                    lastOutputMuted = e.data.output_muted === true;
                    lastInputMuted = e.data.input_muted === true;
                }
                if (!audio.hasSynced || root.suppressStartupEvents || root.guardVolume < 0) { root.seedGuards(); return; }
                if (isFinite(v) && Math.abs(v - guardVolume) > 1) { guardVolume = v; root.enqueue("volume", "Volume", "\uF028", v, 100, root.priVolume, 2000); }
                else if (e.data.output_muted !== undefined && e.data.output_muted !== previousOutputMuted) { root.enqueue("output-mute", e.data.output_muted ? "Muted" : "Unmuted", e.data.output_muted ? "\uF026" : "\uF028", v || 0, 100, root.priOutputMute, 2000); }
                else if (e.data.input_muted !== undefined && e.data.input_muted !== previousInputMuted) { root.enqueue("input-mute", e.data.input_muted ? "Mic Muted" : "Mic Live", "\uF130", 0, 1, root.priInputMute, 2000); }
                return;
            }
            if (e.provider === "brightness" && e.data) {
                var b = Number(e.data.percentage);
                if (!brightness.hasSynced || root.suppressStartupEvents || root.guardBrightness < 0) { root.seedGuards(); return; }
                if (isFinite(b) && Math.abs(b - guardBrightness) > 1) { guardBrightness = b; root.enqueue("brightness", "Brightness", "\uF185", b, 100, root.priBrightness, 2000); }
                return;
            }
            if (e.provider === "media") {
                var md = e.data || {};
                if (md.playback_status === "playing" || md.title) {
                    mediaTitle = md.title || "";
                    mediaArtist = md.artists ? (Array.isArray(md.artists) ? md.artists.join(", ") : String(md.artists)) : "";
                    mediaArtwork = md.artwork_url || md.artwork_cache || "";
                    mediaStatus = md.playback_status || "";
                    mediaAvailable = true;
                    root.enqueue("media", mediaTitle, "\uF001", 50, 100, root.priMedia, 5000);
                } else {
                    mediaAvailable = false;
                }
                return;
            }
            if (e.provider === "notifications") {
                var nd = e.data || {};
                root.enqueue("notification", nd.summary || nd.app_name || "Notification", "\uF0F3", 1, 1, root.priNotification, 5000);
                return;
            }
            if (e.provider === "power") {
                var pd = e.data || {};
                if (pd.warning === "low_battery" || pd.warning === "critical_battery")
                    root.enqueue("battery-warning", "Battery: " + Math.round(pd.percentage || 0) + "%", "\uF244", 1, 1, root.priBattery, 8000);
                return;
            }
        }
    }

    Connections {
        target: audio
        function onOutputVolumeChanged() {
            root.seedGuards();
            if (!audio.hasSynced || root.suppressStartupEvents || root.guardVolume < 0) return;
            if (Math.abs(audio.outputVolume - guardVolume) <= 1) return;
            guardVolume = audio.outputVolume;
            root.enqueue("volume", "Volume", "\uF028", audio.outputVolume, audio.maxVolume || 100, root.priVolume, 2000);
        }
    }

    Connections {
        target: brightness
        function onPercentageChanged() {
            root.seedGuards();
            if (!brightness.hasSynced || root.suppressStartupEvents || root.guardBrightness < 0) return;
            if (Math.abs(brightness.percentage - guardBrightness) <= 1) return;
            guardBrightness = brightness.percentage;
            root.enqueue("brightness", "Brightness", "\uF185", brightness.percentage, 100, root.priBrightness, 2000);
        }
    }

    Connections { target: audio; function onHasSyncedChanged() { root.seedGuards(); } }
    Connections { target: brightness; function onHasSyncedChanged() { root.seedGuards(); } }

    Timer { id: hideTimer; interval: 2000; repeat: false; onTriggered: root.deactivate() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { root.now = new Date(); if (root.timerActive && root.timerRemainingSeconds > 0) { root.timerRemainingSeconds--; root.activityLabel = "Timer " + root.formatTime(root.timerRemainingSeconds); if (root.timerRemainingSeconds <= 0) { root.timerActive = false; root.deactivate(); } } } }
    Timer { id: startupGuardTimer; interval: 5000; repeat: false; running: true; onTriggered: { root.seedGuards(); root.suppressStartupEvents = false; } }

    // ── Inline calendar ──
    Item {
        id: inlineCalendarHost
        visible: root.calendarExpanded
        z: 20
        width: Theme.Tokens.scaled(520)
        height: Theme.Tokens.scaled(650)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        CalendarSurface.CalendarWidget {
            id: inlineCalendar
            anchors.fill: parent
            screen: root.screen
            noxd: root.noxd
            calModel: root.calModel
        }
        Connections {
            target: inlineCalendar
            function onVisibleChanged() {
                if (!inlineCalendar.visible) root.calendarExpanded = false;
            }
        }
    }

    // ── Launcher ──
    Loader {
        id: launcherLoader
        anchors.fill: islandCard
        anchors.margins: Theme.Tokens.spacingLg
        z: 5
        active: root.launcherVisible
        visible: root.launcherVisible
        sourceComponent: root.launcherComponent
        onLoaded: {
            if (item && typeof item.open === "function") item.open();
        }
    }

    Connections {
        target: launcherLoader.item
        function onVisibleChanged() {
            if (!launcherLoader.item) return;
            if (launcherLoader.item.visible) root.launcherWasVisible = true;
            else if (root.launcherWasVisible) root.finishLauncherClose();
        }
    }

    // ── Island card ──
    Rectangle {
        id: islandCard
        anchors.centerIn: parent
        visible: !root.calendarExpanded
        width: root.launcherVisible ? Theme.Tokens.scaled(620)
            : root.dashboardVisible || root.visualExpanded ? root.expandW
            : Math.max(root.pillW, islandContent.implicitWidth + Theme.Tokens.scaled(18))
        height: parent.height
        radius: root.launcherVisible || root.visualExpanded ? Theme.Tokens.radiusXl : Theme.Tokens.radiusPill
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, Theme.Tokens.glassPanelAlpha)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
        border.width: 1
        Accessible.role: Accessible.Button
        Accessible.name: root.islandPinned
            ? root.labelForState(root.islandState) + ", pinned. Activate to unpin"
            : root.labelForState(root.islandState) + ". Activate to pin"
        Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
        Behavior on radius { enabled: !root.reducedMotion; NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

        // Main content
        RowLayout {
            id: islandContent
            anchors.fill: parent
            visible: !root.launcherVisible && !root.dashboardVisible
            anchors.margins: root.visualExpanded ? Theme.Tokens.spacingLg : Theme.Tokens.spacingSm
            spacing: root.visualExpanded ? Theme.Tokens.spacingMd : Theme.Tokens.spacingSm

            // Left icon
            Text {
                text: iconForState(root.islandState)
                color: Theme.Tokens.tonalPrimary
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: root.visualExpanded ? Theme.Tokens.iconLg : Theme.Tokens.iconSm
                Layout.alignment: Qt.AlignVCenter
            }

            // Center: label + sub-label
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.visualExpanded ? Theme.Tokens.scaled(Theme.Tokens.spacingXs) : 0

                Text {
                    text: labelForState(root.islandState)
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: root.islandState === "idle"
                        ? Theme.Tokens.typographyTitleMedium
                        : root.visualExpanded ? Theme.Tokens.typographyLabelLarge : Theme.Tokens.typographyBodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // Idle expanded: show context-aware sub-label
                Text {
                    visible: root.islandState === "idle" && root.hoverExpanded
                    text: subLabelForState(root.islandState)
                    color: Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Progress bar
                Rectangle {
                    Layout.fillWidth: true
                    height: root.visualExpanded ? 5 : 3
                    radius: 2
                    color: Theme.Tokens.outlineSubtle
                    visible: root.activityMaximum > 1 && root.activityValue >= 0

                    Rectangle {
                        width: parent.width * Math.min(1, root.activityValue / root.activityMaximum)
                        height: parent.height
                        radius: parent.radius
                        color: root.islandState === "brightness" ? Theme.Tokens.stateWarning
                            : root.islandState === "battery-warning" ? Theme.Tokens.stateDanger
                            : Theme.Tokens.tonalPrimary
                        Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // Right: percent or chevron
            Text {
                visible: !root.visualExpanded && root.islandState !== "idle" && root.activityMaximum > 1
                text: root.displayPercent + "%"
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.islandPinned
                text: "\uF08D"
                color: Theme.Tokens.tonalPrimary
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: Theme.Tokens.iconXs
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.visualExpanded && root.panelForIslandState() !== null
                text: "\uF054"
                color: Theme.Tokens.textSecondary
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: Theme.Tokens.iconSm
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ColumnLayout {
            visible: root.dashboardVisible && !root.launcherVisible
            anchors.fill: parent
            anchors.margins: Theme.Tokens.scaled(16)
            spacing: Theme.Tokens.scaled(8)

            RowLayout {
                Layout.fillWidth: true
                Text { text: root.iconForState(root.islandState); color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconSm }
                Text { text: root.islandState === "workspace" ? "WORKSPACE" : root.islandState === "health" ? "SYSTEM" : root.islandState === "connectivity" ? "CONNECTIVITY" : root.islandState === "notification-preview" ? "NOTIFICATIONS" : root.islandState === "updates" ? "UPDATES" : root.islandState === "sync" ? "SYNC" : root.islandState === "provider-health" ? "PROVIDER HEALTH" : "AUDIO & POWER"; color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelLarge; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.islandPinned
                    text: "\uF08D  Pinned"
                    color: Theme.Tokens.tonalPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                }
                // Distinct "Open" action: expands the island to the real
                // panel/surface registered for this state. Pin/unpin is
                // handled by tapping the island body itself.
                FocusScope {
                    id: dashboardOpenButton
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: root.openButtonAccessibleName()
                    implicitWidth: openLabel.implicitWidth + Theme.Tokens.scaled(14)
                    implicitHeight: Theme.Tokens.scaled(22)
                    visible: root.openPanelForState() !== null
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.scaled(11); color: dashboardOpenButton.activeFocus ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.85) : "transparent"; border.color: dashboardOpenButton.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: dashboardOpenButton.activeFocus ? 1 : 0 }
                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: "Open ›"
                        color: Theme.Tokens.textSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                    }
                    TapHandler { onTapped: root.openPanelFromIsland() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Keys.onReturnPressed: root.openPanelFromIsland()
                    Keys.onSpacePressed: root.openPanelFromIsland()
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.outlineSubtle }

            ColumnLayout {
                visible: root.islandState === "workspace"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: "Active  " + String(root.hyprland.activeWorkspace && (root.hyprland.activeWorkspace.name || root.hyprland.activeWorkspace.id) || "—"); color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: root.activeApp !== "" ? root.activeApp + "  ·  " + root.activeWin : "No focused application"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: "Windows  " + (root.hyprland.windows ? root.hyprland.windows.length : 0) + "  ·  Occupied workspaces  " + (root.hyprland.workspaces ? root.hyprland.workspaces.filter(function(w) { return Number(w.windows || 0) > 0; }).length : 0); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { text: "Scroll the workspace capsule to switch."; color: Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
            }

            ColumnLayout {
                visible: root.islandState === "health"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(6)
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "CPU  " + (root.systemModel.status === "live" || root.systemModel.status === "stale" ? Math.round(root.systemModel.cpuUsage) + "%" : "—"); color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: root.systemModel.cpuFreqAvailable ? (root.systemModel.cpuFreq / 1000).toFixed(1) + " GHz" : "Frequency unavailable"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                }
                Text { text: root.systemModel.status === "live" ? "Live telemetry · " + root.systemModel.dataSource : root.systemModel.status === "stale" ? "Stale telemetry · " + Math.round(root.systemModel.ageMs / 1000) + "s old · " + root.systemModel.dataSource : root.systemModel.status === "pending" ? "Waiting for telemetry" : "Telemetry unavailable"; color: root.systemModel.status === "live" ? Theme.Tokens.stateSuccess : root.systemModel.status === "stale" ? Theme.Tokens.stateWarning : Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { visible: root.systemModel.status === "live" || root.systemModel.status === "stale"; text: root.systemModel.loadAvailable ? "Load  " + root.systemModel.load1.toFixed(2) + " · " + root.systemModel.load5.toFixed(2) + " · " + root.systemModel.load15.toFixed(2) : "Load unavailable"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { visible: root.systemModel.status === "live" || root.systemModel.status === "stale"; text: "Memory  " + (root.systemModel.memUsed / 1048576).toFixed(1) + " / " + (root.systemModel.memTotal / 1048576).toFixed(1) + " GiB" + (root.systemModel.swapAvailable ? "  ·  Swap " + (root.systemModel.swapUsed / 1048576).toFixed(1) + " GiB" : ""); color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall }
                Text { visible: root.systemModel.status === "live" || root.systemModel.status === "stale"; text: "Thermals  CPU " + (root.systemModel.cpuTempAvailable ? Math.round(root.systemModel.cpuTemp) + "°C" : "—") + "  ·  GPU " + (root.systemModel.gpuTempAvailable ? Math.round(root.systemModel.gpuTemp) + "°C" : "—"); color: root.systemModel.cpuTempAvailable && root.systemModel.cpuTemp >= 85 ? Theme.Tokens.stateDanger : root.systemModel.cpuTempAvailable && root.systemModel.cpuTemp >= 75 ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall }
                Text { visible: (root.systemModel.status === "live" || root.systemModel.status === "stale") && root.systemModel.gpuAvailable; text: (root.systemModel.gpuSource === "nvidia" ? "NVIDIA compute  " : "Integrated graphics  ") + Math.round(root.systemModel.gpuUsage) + "%  ·  VRAM " + Math.round(root.systemModel.gpuMemUsed) + " / " + Math.round(root.systemModel.gpuMemTotal) + " MiB" + (root.systemModel.gpuPowerAvailable ? "  ·  " + root.systemModel.gpuPower.toFixed(1) + " W" : ""); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { text: "Process history, fan, NVMe and throttling appear only when exposed by the host."; color: Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }

            ColumnLayout {
                visible: root.islandState === "connectivity"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: (root.network.connectedSsid || (root.network.ethernet && root.network.ethernet.length ? "Ethernet" : "Offline")); color: root.network.connectivity === "full" ? Theme.Tokens.textPrimary : Theme.Tokens.stateWarning; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: "Signal  " + (root.network.signalStrength !== null ? Math.round(root.network.signalStrength) + "%" : "unavailable") + "  ·  Internet " + root.network.connectivity; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { text: "IPv4  " + (root.network.ipv4 && root.network.ipv4.length ? String(root.network.ipv4[0].address || root.network.ipv4[0]) : "unavailable"); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { text: "VPN  " + (root.network.vpn && root.network.vpn.length ? "connected" : "not connected"); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Text { text: "Bluetooth  " + (root.bluetooth.connectedDevices && root.bluetooth.connectedDevices.length ? root.bluetooth.connectedDevices.map(function(d) { return (d.name || "Device") + (d.battery !== undefined && d.battery !== null ? " " + Math.round(d.battery) + "%" : ""); }).join("  ·  ") : "no connected devices"); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: "Throughput, gateway and ping are hidden until provided by the network snapshot."; color: Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
            }

            ColumnLayout {
                visible: root.islandState === "audio-power"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: "Output  " + (root.audio.outputMuted ? "Muted" : root.audio.outputVolumePercent + "%"); color: root.audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: root.audio.outputName || "Default output"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: "Microphone  " + (root.audio.inputMuted ? "Muted" : root.audio.inputVolumePercent + "%"); color: root.audio.inputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.outlineSubtle }
                Text { visible: root.battery.present; text: "Battery  " + Math.round(root.battery.percentage || 0) + "%  ·  " + root.battery.chargingState; color: root.battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { visible: root.battery.present; text: "Health  " + (root.battery.healthPercentage !== null ? Math.round(root.battery.healthPercentage) + "%" : "unavailable") + "  ·  remaining time " + (root.battery.timeToEmptySeconds || root.battery.timeToFullSeconds ? Math.round((root.battery.timeToEmptySeconds || root.battery.timeToFullSeconds) / 60) + " min" : "unavailable"); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
            }

            ColumnLayout {
                visible: root.islandState === "notification-preview"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: root.notificationModel && root.notificationModel.dnd ? "Do Not Disturb enabled" : ((root.notificationModel && root.notificationModel.notifications ? root.notificationModel.notifications.length : 0) + " unread"); color: root.notificationModel && root.notificationModel.dnd ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Repeater {
                    model: Math.min(3, root.notificationModel && root.notificationModel.notifications ? root.notificationModel.notifications.length : 0)
                    delegate: Text { required property int index; text: { var notes = root.notificationModel && root.notificationModel.notifications ? root.notificationModel.notifications : []; var n = notes[notes.length - 1 - index] || {}; return (n.app_name || "Notification") + "  ·  " + (n.summary || n.body || ""); } color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                Text { visible: !root.notificationModel || !root.notificationModel.notifications || root.notificationModel.notifications.length === 0; text: "No unread notifications"; color: Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
            }

            ColumnLayout {
                visible: root.islandState === "updates"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: !root.updates.checked ? "Checking package databases…" : root.updates.count > 0 ? root.updates.count + " updates are available" : "System packages are up to date"; color: root.updates.count > 0 ? Theme.Tokens.stateInfo : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: root.updates.tooltip || "Click the update capsule to open the updater; right-click to refresh."; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }

            ColumnLayout {
                visible: root.islandState === "sync"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: root.transfer.hasActiveTransfers ? "Transfers are active" : root.syncthing.syncing ? "Syncthing is synchronizing" : root.syncthing.hasErrors ? "Sync needs attention" : "Sync is idle"; color: root.syncthing.hasErrors ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: root.syncthing.serviceActive ? (root.syncthing.apiReachable ? "Syncthing service and API are reachable" : "Syncthing service is running; API is unavailable") : "Syncthing service is not active"; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }

            ColumnLayout {
                visible: root.islandState === "provider-health"
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(7)
                Text { text: "One or more desktop data providers are degraded"; color: Theme.Tokens.stateWarning; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall; font.bold: true }
                Text { text: "Open System controls for the current source status. Unavailable values remain marked rather than being guessed."; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }

        // ── Input handlers ──
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                var prevInside = root.engagement.islandHovered;
                if (prevInside === hovered) return;
                engagement = HoverEngagement.recordIslandHover(engagement, hovered);
                if (hovered) {
                    // The user is now over the island body — cancel any
                    // pending close and adopt the active context.
                    root.activeTransitToken = { generation: engagement.generation, deadline: 0 };
                    pointerGraceTimer.stop();
                    if (root.islandState === "idle" && !engagement.pin.active && !engagement.critical.active && !manualMode) {
                        hoverExpanded = true;
                    }
                } else {
                    if (HoverEngagement.isAnySourceHovered(engagement)) {
                        // Pointer moved to a different source chip — that
                        // source's release handler will re-arm the timer.
                        return;
                    }
                    if (engagement.pin.active) return;
                    if (engagement.critical.active) return;
                    if (engagement.osd.active) return;
                    if (root.panelOpen || root.launcherVisible) return;
                    root.armTransitTimer();
                }
            }
        }

        // Click toggles a pin on the current context. The "Open" action is
        // exposed separately via the dashboard's "Open ›" affordance and
        // remains bound to the panel-coordinator.
        TapHandler {
            enabled: !root.launcherVisible
            onTapped: root.pinToggle()
        }

        // Wheel: cycle contexts when idle and hovered
        WheelHandler {
            onWheel: function(e) {
                if (root.islandState === "idle" && root.engagement.islandHovered) {
                    if (e.angleDelta.y > 0) root.cycleContextUp();
                    else root.cycleContextDown();
                    e.accepted = true;
                }
            }
        }

        // Middle-click: return to auto mode
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: root.exitManualMode()
        }
    }

    // ── Context label helpers ──
    function iconForState(state) {
        switch (state) {
            case "idle":          return "\uF017";
            case "volume":         return "\uF028";
            case "brightness":     return "\uF185";
            case "media":         return "\uF001";
            case "mic":           return "\uF130";
            case "recording":     return "\uF111";
            case "timer":         return "\uF017";
            case "notification":  return "\uF0F3";
            case "output-mute":   return "\uF026";
            case "input-mute":    return "\uF130";
            case "file-transfer": return "\uF093";
            case "ai-completion": return "\uF0C3";
            case "build-result":  return "\uF00C";
            case "battery-warning": return "\uF244";
            case "network-warning": return "\uF1EB";
            case "health":         return "\uF2DB";
            case "connectivity":   return "\uF1EB";
            case "audio-power":    return "\uF028";
            case "workspace":      return "\uF2D2";
            case "notification-preview": return "\uF0F3";
            case "focused-app":   return "\uF2D2";
            case "updates":       return "\uF019";
            case "sync":          return "\uF2EF";
            case "provider-health": return "\uF071";
            case "network":       return "\uF1EB";
            case "battery":       return "\uF240";
            case "clock":         return "\uF017";
            default:              return "\uF017";
        }
    }

    function labelForState(state) {
        if (state === "idle") {
            var context = root.activeApp !== "" ? " · " + root.activeApp : "";
            return Qt.formatDate(root.now, "ddd d") + " · " + Qt.formatTime(root.now, "HH:mm") + context;
        }
        if (state === "focused-app") return root.activeApp !== "" ? root.activeApp : "No focused app";
        if (state === "updates") return root.updates && root.updates.checked ? (root.updates.count > 0 ? root.updates.count + " updates" : "System up to date") : "Checking updates";
        if (state === "sync") return root.syncthing && root.syncthing.hasErrors ? "Sync needs attention" : root.syncthing && root.syncthing.syncing ? "Syncing" : "Sync idle";
        if (state === "provider-health") return "Provider health warning";
        if (state === "network") return root.network && root.network.connectivity === "full" ? (root.network.connectedSsid || "Online") : "Network " + (root.network ? root.network.connectivity : "unavailable");
        if (state === "battery") return root.battery && root.battery.present ? "Battery " + Math.round(root.battery.percentage || 0) + "%" : "Battery unavailable";
        return root.activityLabel || state;
    }

    function subLabelForState(state) {
        if (state !== "idle") return "";
        var parts = [];
        var dateStr = Qt.formatDate(root.now, "ddd, d MMM");
        parts.push(dateStr);
        if (manualMode) {
            parts.push("Manual · middle-click to reset");
        } else if (activeApp !== "") {
            parts.push(activeApp);
            if (activeWin !== "" && activeWin !== activeApp) parts.push(activeWin);
        } else if (activeWin !== "") {
            parts.push(activeWin);
        }
        parts.push("scroll to cycle");
        return parts.join("  ·  ");
    }

    // ── Launcher control ──
    function openLauncher() {
        if (root.launcherOpen) return;
        if (root.calendarExpanded) {
            inlineCalendar.close();
            root.calendarExpanded = false;
        }
        root.launcherWasVisible = false;
        root.launcherClosing = false;
        root.launcherOpen = true;
        Qt.callLater(function() { root.forceActiveFocus(); });
    }

    function finishLauncherClose() {
        root.launcherWasVisible = false;
        root.launcherClosing = false;
        root.launcherOpen = false;
    }

    function closeLauncher() {
        if (!root.launcherVisible) return;
        root.launcherClosing = true;
        if (launcherLoader.item && typeof launcherLoader.item.close === "function") {
            launcherLoader.item.close();
        } else {
            root.finishLauncherClose();
        }
    }

    function toggleLauncher() {
        if (root.launcherVisible) root.closeLauncher();
        else root.openLauncher();
    }

    function islandGeometry() {
        var p = islandCard.mapToItem(null, 0, 0);
        return Qt.rect(p.x, p.y, islandCard.width, islandCard.height);
    }

    // ── Public helpers ──
    function formatTime(s) { var m = Math.floor(s / 60); var r = s % 60; return m + ":" + (r < 10 ? "0" : "") + r; }
    function startTimer(s) { if (s <= 0) return; timerTotalSeconds = s; timerRemainingSeconds = s; timerActive = true; enqueue("timer", "Timer " + formatTime(s), "\uF017", 1, 1, priTimer, Math.max(1000, s * 1000)); }
    function showRecording() { enqueue("recording", "Recording", "\uF111", 0, 1, priRecording, 86400000); }
    function stopRecording() { if (islandState === "recording") deactivate(); }
    function showNotification(s, b) { enqueue("notification", s || "Notification", "\uF0F3", 0, 1, priNotification, 5000); }
    function showFileTransfer(name, progress) { fileTransferName = name || ""; fileTransferProgress = progress || 0; fileTransferActive = true; enqueue("file-transfer", name || "File transfer", "\uF093", progress, 1, priFileTransfer, 8000); }
    function showAiCompletion(text) { aiCompletionText = text || ""; enqueue("ai-completion", text ? "AI: " + text : "AI completion", "\uF0C3", 0, 1, priAiCompletion, 6000); }
    function showBuildResult(text, success) { buildResultText = text || ""; buildResultStatus = success ? 1 : 2; enqueue("build-result", text || (success ? "Build succeeded" : "Build failed"), success ? "\uF00C" : "\uF00D", 0, 1, priBuildResult, 10000); }
    function showBatteryWarning(pct) { enqueue("battery-warning", "Battery: " + Math.round(pct) + "%", "\uF244", 1, 1, priBattery, 8000); }
    function showNetworkWarning(msg) { enqueue("network-warning", msg || "Network issue", "\uF1EB", 1, 1, priNetwork, 6000); }
}
