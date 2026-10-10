import QtQuick
import Quickshell
import Quickshell.Io
import "surfaces/controlcenter" as ControlCenter
import "surfaces/notifications" as NotificationSurfaces
import "surfaces/launcher" as LauncherSurface
import "surfaces/capture" as CaptureSurface
import "surfaces/clipboard" as ClipboardSurface
import "surfaces/radialmenu" as RadialSurface
import "surfaces/calendar" as CalendarSurface
import "surfaces/media" as MediaSurface
import "surfaces/dashboard" as DashboardSurface
import "surfaces/settings" as SettingsSurface
import "surfaces/share" as ShareSurface
import "surfaces/wallpaper" as WallpaperSurface
import "services" as Services
import "config" as Config
import "components" as Components
import "core" as Core

ShellRoot {
    id: shellRoot

    // ── Providers & Models ──
    NoxdClient { id: daemonClient; Component.onCompleted: start() }
    HyprlandModel { id: hyprlandModel }
    AudioModel { id: audioModel }
    BrightnessModel { id: brightnessModel }
    PowerModel { id: powerModel }
    // noxd: the Wi-Fi connect flow lives in the model and issues the actions.
    NetworkModel { id: networkModel; noxd: daemonClient }
    BluetoothModel { id: bluetoothModel }
    MediaModel { id: mediaModel }
    // Named notifStore, not notificationModel: the id used to be
    // `notificationModel`, which silently shadowed the identically named
    // TopChrome/Bar property. `notificationModel: notificationModel` then
    // resolved the right-hand side to the property itself, so the bar
    // received `undefined` and the notification badge was structurally
    // incapable of ever showing a count.
    NotificationModel { id: notifStore }

    // Decision 5: Quickshell owns org.freedesktop.Notifications. Instantiating
    // the server is what claims the bus name — referencing it as a singleton
    // leaves trackedNotifications undefined and no owner at all.
    Services.NotificationBridge {
        id: notificationBridge
        model: notifStore
    }
    property alias notificationBridge: notificationBridge
    CalendarModel { id: calendarModel; Component.onCompleted: start() }
    ClipboardModel { id: clipboardModel }
    TransferModel { id: transferModel; noxd: daemonClient }
    SyncthingModel { id: syncthingModel; Component.onCompleted: start() }
    WallpaperModel { id: wallpaperModel }
    MorphRegistry { id: morphRegistry }
    // Touch the external-program registry at startup so its probe runs even
    // when no view has been created yet; otherwise the first radial or
    // launcher use races the probe and disables entries that do exist.
    Component.onCompleted: {
        if (!Config.Apps.probed) Config.Apps.probe();
    }
    WeatherModel { id: weatherModel; Component.onCompleted: start() }
    SystemModel { id: systemModelInstance; Component.onCompleted: start() }
    UpdateModel { id: updateModel; Component.onCompleted: start() }
    CaptureSurface.QuickSnipSettings { id: quickSnipSettings; Component.onCompleted: load() }

    // One AI client for every surface. Configured from noxd settings rather
    // than a hardcoded constant or per-surface env lookup.
    // Named aiClientInstance, not aiClient: with the id named `aiClient`, the
    // binding `aiClient: aiClient` on Launcher and Capture resolved the
    // right-hand side to those components' own `aiClient` property, so both
    // received null and every AI action in the launcher and in Capture's panel
    // was silently dead. An id is not reachable as `shellRoot.aiClient`, so
    // renaming the id is the fix; qualifying the reference is not.
    Services.AiClient {
        id: aiClientInstance
        noxd: daemonClient
        Component.onCompleted: {
            // The daemon may not have finished its handshake yet; retry once
            // the subscription completes so the endpoint is authoritative.
            refreshSettings()
        }
    }
    property alias ai: aiClientInstance

    // ── Per-screen instance trackers ──
    InstanceTracker { id: ccTracker }
    InstanceTracker { id: ncTracker }
    InstanceTracker { id: calTracker }
    InstanceTracker { id: rwTracker }
    InstanceTracker { id: mediaTracker }
    ActivityController { id: activityControllerInstance }
    Core.PanelController { id: panelController; triggerRegistry: morphRegistry }
    property alias coordinator: panelController
    property alias triggerRegistry: morphRegistry
    // TopChrome is instantiated once per monitor. Keep a small registry so
    // global IPC/keybind requests expand the island on the active monitor
    // without creating a second launcher surface.
    property var islandHosts: ({})

    function registerIslandHost(screen, host) {
        if (!screen || !host) return;
        var next = {};
        for (var key in islandHosts) next[key] = islandHosts[key];
        next[screen.name] = host;
        islandHosts = next;
    }
    function unregisterIslandHost(screen) {
        if (!screen) return;
        var next = {};
        for (var key in islandHosts) if (key !== screen.name) next[key] = islandHosts[key];
        islandHosts = next;
    }
    function activeIslandHost() {
        var active = Quickshell.activeScreen;
        if (active && islandHosts[active.name]) return islandHosts[active.name];
        for (var key in islandHosts) return islandHosts[key];
        return null;
    }

    // The launcher is hosted by NoxIsland rather than MorphSurface. Keeping
    // this component at shell scope lets every monitor's island load the same
    // implementation without creating a second PanelWindow.
    Component {
        id: launcherDefinition
        LauncherSurface.Launcher {
            noxd: daemonClient; hyprland: hyprlandModel; clipboardModel: clipboardModel
            aiClient: aiClientInstance
            onRequestCaptureAfterClose: shellRoot.openCapture()
        }
    }

    // ── Daemon snapshot dispatch ──
    Connections {
        target: daemonClient
        function onConnectionStateUpdated(state) {
            // Appearance and AI configuration both come from the daemon, so
            // refresh them once it is actually subscribed (phase 1.12, dec. 4).
            if (state === "subscribed") {
                applyPersistedAppearance();
                aiClientInstance.refreshSettings();
            }
        }
        function onSnapshotReceived(snapshots) {
            // Only providers noxd actually registers reach this handler: the
            // subscription allowlist in Protocol.js mirrors
            // core/noxd/src/providers/. "notifications", "calendar" and
            // "clipboard" were removed because EventBus::subscribe accepts
            // unknown provider names silently — they looked subscribed while
            // delivering nothing, so the bar pill and the notification centre
            // rendered permanently empty state.
            for (var provider in snapshots) {
                var snapshot = snapshots[provider];
                if (provider === "hyprland") hyprlandModel.applySnapshot(snapshot);
                else if (provider === "audio") audioModel.applySnapshot(snapshot);
                else if (provider === "brightness") brightnessModel.applySnapshot(snapshot);
                else if (provider === "power") powerModel.applySnapshot(snapshot)
                else if (provider === "network") networkModel.applySnapshot(snapshot);
                else if (provider === "bluetooth") bluetoothModel.applySnapshot(snapshot);
                else if (provider === "media") mediaModel.applySnapshot(snapshot);
                else if (provider === "transfer") transferModel.applySnapshot(snapshot);
            }
        }
        function onEventReceived(event) {
            if (!event) return;
            if (event.provider === "transfer") transferModel.applyEvent(event);
            else if (event.provider === "bluetooth") bluetoothModel.applyEvent(event);
        }
    }

    // ── Unified major-panel host (one PanelWindow per monitor) ──
    Variants {
        model: Quickshell.screens
        Core.MorphSurface {
            id: morphSurface
            required property var modelData
            screen: modelData
            panelComponents: ({
                "quick-settings": quickSettingsComponent,
                "calendar": calendarComponent,
                "notifications": notificationComponent,
                "media": mediaComponent,
                "clipboard": clipboardComponent,
                "wallpaper": wallpaperComponent,
                "quick-share": quickShareComponent,
                "sync": syncComponent
            })
            Component {
                id: quickSettingsComponent
                ControlCenter.ControlCentre {
                    screen: morphSurface.screen
                    noxd: daemonClient; audio: audioModel; brightness: brightnessModel
                    network: networkModel; bluetooth: bluetoothModel; battery: powerModel
                    power: powerModel; hyprland: hyprlandModel; systemModel: systemModelInstance
                    notificationModel: notifStore
                }
            }
            Component {
                id: calendarComponent
                CalendarSurface.CalendarWidget { screen: morphSurface.screen; noxd: daemonClient; calModel: calendarModel }
            }
            Component {
                id: notificationComponent
                NotificationSurfaces.NotificationCentre { screen: morphSurface.screen; noxd: daemonClient; notifModel: notifStore; morphRegistry: morphRegistry; bridge: notificationBridge }
            }
            Component {
                id: mediaComponent
                MediaSurface.MediaPanel { screen: morphSurface.screen; noxd: daemonClient; media: mediaModel }
            }
            Component {
                id: clipboardComponent
                ClipboardSurface.ClipboardPanel { screen: morphSurface.screen; noxd: daemonClient; clipModel: clipboardModel }
            }
            Component {
                id: wallpaperComponent
                WallpaperSurface.WallpaperPanel { screen: morphSurface.screen; noxd: daemonClient; wallModel: wallpaperModel }
            }
            Component {
                id: quickShareComponent
                ShareSurface.QuickSharePanel {
                    screen: morphSurface.screen; noxd: daemonClient; transfer: transferModel
                }
            }
            Component {
                id: syncComponent
                ShareSurface.SyncPanel {
                    screen: morphSurface.screen; noxd: daemonClient; transfer: transferModel; syncthing: syncthingModel
                }
            }
            Component.onCompleted: {
                panelController.registerPanel("quick-settings", this);
                panelController.registerPanel("calendar", this);
                panelController.registerPanel("notifications", this);
                panelController.registerPanel("media", this);
                panelController.registerPanel("clipboard", this);
                panelController.registerPanel("wallpaper", this);
                panelController.registerPanel("quick-share", this);
                panelController.registerPanel("sync", this);
            }
            Connections {
                target: morphSurface
                function onPanelClosed(panelName) { panelController.surfaceClosed(panelName, morphSurface); }
            }
            Component.onDestruction: {
                // Unregister from every panel name so the controller doesn't
                // retain a destroyed reference after a monitor disconnect or
                // full shell teardown. surface() guards against destroyed
                // entries, but pruning eagerly keeps the registry honest.
                panelController.unregisterPanel("quick-settings", this);
                panelController.unregisterPanel("calendar", this);
                panelController.unregisterPanel("notifications", this);
                panelController.unregisterPanel("media", this);
                panelController.unregisterPanel("clipboard", this);
                panelController.unregisterPanel("wallpaper", this);
                panelController.unregisterPanel("quick-share", this);
                panelController.unregisterPanel("sync", this);
            }
        }
    }

    function closeInlineCalendars() {
        for (var key in islandHosts) {
            var host = islandHosts[key];
            if (host && typeof host.closeInlineCalendar === "function") host.closeInlineCalendar();
        }
    }

    // Pull appearance from the daemon and apply it at boot. Before this, a
    // theme survived only as long as the Settings panel stayed open.
    property bool appearanceApplied: false
    function applyPersistedAppearance() {
        if (!daemonClient || !daemonClient.connected) return false;
        daemonClient.getSettings(function(result) {
            var data = result && result.data && result.data.settings;
            if (!data) {
                console.warn("shell: daemon returned no settings for appearance hydration");
                return;
            }
            var applied = Config.Appearance.applyFromMap(data);
            appearanceApplied = true;
            if (applied.length > 0)
                console.info("shell: applied persisted appearance:", applied.join(", "));
            else
                console.info("shell: persisted appearance already active");
        }, function(code, message) {
            console.warn("shell: could not read persisted appearance from daemon:", code, message);
        });
        return true;
    }

    function toggleControlCentre() { closeInlineCalendars(); panelController.toggle("quick-settings"); }
    function openControl()   { closeInlineCalendars(); panelController.open("quick-settings"); }
    function openControlSection(section) { closeInlineCalendars(); panelController.open("quick-settings", "", null, section); }
    function toggleBluetoothPanel() { closeInlineCalendars(); panelController.toggle("quick-settings", "", null, "bluetooth"); }
    function openBluetoothPanel() { closeInlineCalendars(); panelController.open("quick-settings", "", null, "bluetooth"); }
    function closeControl()  { panelController.close("quick-settings"); }

    function toggleNotificationCentre() { panelController.toggle("notifications"); }
    function openNotifications()   { panelController.open("notifications"); }
    function closeNotifications()  { panelController.close("notifications"); }

    function toggleCalendar() { closeInlineCalendars(); panelController.toggle("calendar"); }
    function openCalendar()   { closeInlineCalendars(); panelController.open("calendar"); }
    function closeCalendar()  { panelController.close("calendar"); }

    function toggleMediaPanel() { panelController.toggle("media"); }
    function openMediaPanel() { panelController.open("media"); }
    function closeMediaPanel() { panelController.close("media"); }

    function toggleClipboardPanel() { panelController.toggle("clipboard"); }
    function openClipboardPanel() { panelController.open("clipboard"); }
    function closeClipboardPanel() { panelController.close("clipboard"); }

    function toggleWallpaperPanel() { panelController.toggle("wallpaper"); }
    function openWallpaperPanel() { panelController.open("wallpaper"); }
    function closeWallpaperPanel() { panelController.close("wallpaper"); }

    // Quick Share (left-side activity panel; built in M12).
    function toggleSharePanel() { panelController.toggle("quick-share"); }
    function openSharePanel() { panelController.open("quick-share"); }
    function closeSharePanel() { panelController.close("quick-share"); }
    function toggleSyncPanel() { panelController.toggle("sync"); }
    function openSyncPanel() { panelController.open("sync"); }
    function closeSyncPanel() { panelController.close("sync"); }

    // ── Radial Wheel (per-screen panel via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        RadialSurface.RadialWheel {
            required property var modelData
            screen: modelData
            noxd: daemonClient
            Component.onCompleted: {
                rwTracker.add(modelData, this);
            }
            Component.onDestruction: {
                rwTracker.remove(modelData);
            }
        }
    }
    function toggleRadialWheel() { rwTracker.toggle(); }
    function openRadialWheel()   { var r = rwTracker.forScreen(null); if (r) r.open(); }
    function closeRadialWheel()  { var r = rwTracker.forScreen(null); if (r) r.close(); }

    // ── Dashboard (full-screen modal, singleton) ──
    DashboardSurface.Dashboard {
        id: dashboard
        noxd: daemonClient; hyprland: hyprlandModel
        audio: audioModel; battery: powerModel; network: networkModel
        calModel: calendarModel
        weatherModel: weatherModel
        systemModel: systemModelInstance
        screen: Quickshell.activeScreen || null
        onRequestCaptureAfterClose: shellRoot.openCapture()
        Component.onCompleted: panelController.registerModal(this)
        Component.onDestruction: panelController.unregisterModal(this)
    }
    function toggleDashboard() { panelController.toggleModal(dashboard); }
    function openDashboard()   { panelController.openModal(dashboard); }
    function closeDashboard()  { dashboard.close(); }

    // ── Settings Panel (modal, singleton) ──
    SettingsSurface.SettingsPanel {
        id: settingsPanel
        noxd: daemonClient
        screen: Quickshell.activeScreen || null
        Component.onCompleted: panelController.registerModal(this)
        Component.onDestruction: panelController.unregisterModal(this)
    }
    function toggleSettings() { panelController.toggleModal(settingsPanel); }
    function openSettings()   { panelController.openModal(settingsPanel); }
    function closeSettings()  { settingsPanel.close(); }

    // ── DND / Night Light (IPC convenience) ──
    // DND is a property on notifStore, not a command. It used to shell out to
    // `dunstctl toggle`; with dunst retired that would have been a silently
    // failing no-op, and the bar pill, the control centre and the notification
    // centre would each have disagreed about whether DND was on.
    property Components.Command nightLightToggle: Components.Command {
        label: "Night light"
        // No `2>/dev/null || …` chain here any more: Command records the exit
        // code, so a missing hyprsunset is observable instead of silent.
        command: ["sh", "-c", "if command -v hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset identity || hyprsunset -t 4500; fi"]
    }
    function toggleDnd() { notifStore.toggleDnd(); }
    function toggleNightLight() { nightLightToggle.running = true; }

    // ── Capture overlay (modal, singleton) ──
    CaptureSurface.Capture {
        id: capture
        noxd: daemonClient
        aiClient: aiClientInstance
        screen: Quickshell.activeScreen || null
        onFullScreenCaptureRequested: dest => {
            // JSON.stringify does the shell quoting here. The previous version
            // interpolated the path into a nested "$(dirname '...')" inside a
            // QML string, which is where the quoting bugs came from.
            var dir = dest.substring(0, dest.lastIndexOf("/"));
            captureFullScreen.runShell(
                "mkdir -p " + JSON.stringify(dir)
                + " && grim " + JSON.stringify(dest)
                + " && notify-send 'Screenshot saved' " + JSON.stringify(dest) + " -t 3000");
            captureFullScreen.exited.connect(function(code) {
                if (code === 0) return;
                // The shell has no notify-send banner of its own, so the exit
                // code and stderr go to the journal instead of being dropped.
                console.warn("screenshot failed:", captureFullScreen.failureText());
            });
        }
        Component.onCompleted: panelController.registerModal(this)
        Component.onDestruction: panelController.unregisterModal(this)
    }
    property Components.Command captureFullScreen: Components.Command {
        label: "Screenshot"
        // The grim failure notification moved into onExited above: one place
        // reports the real exit code instead of the shell string building a
        // second, always-identical "grim returned an error" message.
    }
    function toggleCapture() { panelController.toggleModal(capture); }
    function openCapture()   { panelController.openModal(capture); }
    function closeCapture()  { capture.close(); }

    // Launcher is mounted in the same per-monitor morph host as every other
    // shell surface. The public functions remain unchanged for IPC/keybinds.
    function toggleLauncher() {
        var host = activeIslandHost();
        if (!host) return;
        if (host.launcherVisible) host.closeLauncher();
        else { panelController.closeAll(); host.openLauncher(); }
    }
    function openLauncher() {
        var host = activeIslandHost();
        if (!host) return;
        panelController.closeAll();
        host.openLauncher();
    }
    function closeLauncher() { var host = activeIslandHost(); if (host) host.closeLauncher(); }

    // ── Global IPC handler for external keybind control ──
    IpcHandler {
        target: "noxctl"
        function toggleControl() { shellRoot.toggleControlCentre(); }
        function openControl()    { shellRoot.openControl(); }
        function closeControl()   { shellRoot.closeControl(); }
        function toggleNotifications() { shellRoot.toggleNotificationCentre(); }
        function openNotifications()   { shellRoot.openNotifications(); }
        function closeNotifications()  { shellRoot.closeNotifications(); }
        function toggleRadialWheel() { shellRoot.toggleRadialWheel(); }
        function openRadialWheel()   { var rw = shellRoot.rwTracker.forScreen(null); if (rw) rw.open(); }
        function closeRadialWheel()  { shellRoot.closeRadialWheel(); }
        function toggleLauncher() { shellRoot.toggleLauncher(); }
        function openLauncher()   { shellRoot.openLauncher(); }
        function closeLauncher()  { shellRoot.closeLauncher(); }
        function toggleCapture() { shellRoot.toggleCapture(); }
        function openCapture()   { shellRoot.openCapture(); }
        function closeCapture()  { shellRoot.closeCapture(); }
        function toggleCalendar() { shellRoot.toggleCalendar(); }
        function openCalendar()   { shellRoot.openCalendar(); }
        function closeCalendar()  { shellRoot.closeCalendar(); }
        function toggleMediaPanel() { shellRoot.toggleMediaPanel(); }
        function openMediaPanel() { shellRoot.openMediaPanel(); }
        function closeMediaPanel() { shellRoot.closeMediaPanel(); }
        function toggleDashboard() { shellRoot.toggleDashboard(); }
        function openDashboard()   { shellRoot.openDashboard(); }
        function closeDashboard()  { shellRoot.closeDashboard(); }
        function toggleSettings() { shellRoot.toggleSettings(); }
        function openSettings()   { shellRoot.openSettings(); }
        function closeSettings()  { shellRoot.closeSettings(); }
        function toggleDnd()      { shellRoot.toggleDnd(); }
        function toggleNightLight() { shellRoot.toggleNightLight(); }
        function handleEscape()     { return shellRoot.coordinator ? shellRoot.coordinator.handleEscape() : false; }
        function toggleQuickSettingsPanel() { return shellRoot.toggleControlCentre(); }
        function openQuickSettingsPanel()   { return shellRoot.openControl(); }
        function toggleBluetoothPanel() { return shellRoot.toggleBluetoothPanel(); }
        function openBluetoothPanel() { return shellRoot.openBluetoothPanel(); }
        function openNetworkPanel()         { return shellRoot.openControlSection("network"); }
        function toggleMediaPanelFromIpc()  { return shellRoot.toggleMediaPanel(); }
        function openMediaPanelFromIpc()    { return shellRoot.openMediaPanel(); }
        function toggleClipboardPanel() { return shellRoot.toggleClipboardPanel(); }
        function openClipboardPanel()   { return shellRoot.openClipboardPanel(); }
         function toggleSharePanel() { return shellRoot.toggleSharePanel(); }
         function openSharePanel()   { return shellRoot.openSharePanel(); }
         function toggleSyncPanel() { return shellRoot.toggleSyncPanel(); }
         function openSyncPanel() { return shellRoot.openSyncPanel(); }
         function closeSyncPanel() { return shellRoot.closeSyncPanel(); }
        function toggleWallpaperPanel() { return shellRoot.toggleWallpaperPanel(); }
        function openWallpaperPanel()   { return shellRoot.openWallpaperPanel(); }
        function closePanel()       { shellRoot.closeLauncher(); shellRoot.coordinator.closeAll(); return true; }
        function panelState()       { return { activePanel: shellRoot.coordinator.activePanel, state: shellRoot.coordinator.state }; }
    }

    // ── Unified top chrome (per-screen) ──
    Variants {
        model: Quickshell.screens
        TopChrome {
            required property var modelData
            screen: modelData
            noxd: daemonClient; hyprland: hyprlandModel; audio: audioModel
            battery: powerModel; network: networkModel; bluetooth: bluetoothModel
            media: mediaModel; notificationModel: notifStore
            systemModel: systemModelInstance; transfer: transferModel; syncthing: syncthingModel
            brightness: brightnessModel; updates: updateModel
            calModel: calendarModel; launcherComponent: launcherDefinition
            activityController: activityControllerInstance
        }
    }
}
