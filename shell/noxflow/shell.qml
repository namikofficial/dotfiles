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
import "components" as Components
import "core" as Core

ShellRoot {
    id: shellRoot

    // ── Providers & Models ──
    NoxdClient { id: daemonClient; Component.onCompleted: start() }
    HyprlandModel { id: hyprlandModel }
    AudioModel { id: audioModel }
    BrightnessModel { id: brightnessModel }
    BatteryModel { id: batteryModel }
    PowerModel { id: powerModel }
    NetworkModel { id: networkModel }
    BluetoothModel { id: bluetoothModel }
    MediaModel { id: mediaModel }
    NotificationModel { id: notificationModel }
    CalendarModel { id: calendarModel; Component.onCompleted: start() }
    ClipboardModel { id: clipboardModel }
    TransferModel { id: transferModel; noxd: daemonClient }
    WallpaperModel { id: wallpaperModel }
    MorphRegistry { id: morphRegistry }
    WeatherModel { id: weatherModel; Component.onCompleted: start() }
    SystemModel { id: systemModel; Component.onCompleted: start() }
    CaptureSurface.QuickSnipSettings { id: quickSnipSettings; Component.onCompleted: load() }

    // ── Per-screen instance trackers ──
    InstanceTracker { id: ccTracker }
    InstanceTracker { id: ncTracker }
    InstanceTracker { id: calTracker }
    InstanceTracker { id: rwTracker }
    InstanceTracker { id: mediaTracker }
    Core.PanelController { id: panelController; triggerRegistry: morphRegistry }
    property alias coordinator: panelController
    property alias surfaceCoordinator: surfaceCoordinatorInstance
    property alias triggerRegistry: morphRegistry

    // ── Surface Coordinator ──
    Components.SurfaceCoordinator {
        id: surfaceCoordinatorInstance
    }

    // ── Daemon snapshot dispatch ──
    Connections {
        target: daemonClient
        function onSnapshotReceived(snapshots) {
            for (var provider in snapshots) {
                var snapshot = snapshots[provider];
                if (provider === "hyprland") hyprlandModel.applySnapshot(snapshot);
                else if (provider === "audio") audioModel.applySnapshot(snapshot);
                else if (provider === "brightness") brightnessModel.applySnapshot(snapshot);
                else if (provider === "power") { batteryModel.applySnapshot(snapshot); powerModel.applySnapshot(snapshot); }
                else if (provider === "network") networkModel.applySnapshot(snapshot);
                else if (provider === "bluetooth") bluetoothModel.applySnapshot(snapshot);
                else if (provider === "media") mediaModel.applySnapshot(snapshot);
                else if (provider === "notifications") notificationModel.applySnapshot(snapshot);
                else if (provider === "calendar") calendarModel.applySnapshot(snapshot);
                else if (provider === "clipboard") clipboardModel.applySnapshot(snapshot);
                else if (provider === "transfer") transferModel.applySnapshot(snapshot);
            }
        }
        function onEventReceived(event) {
            if (event && event.provider === "transfer") transferModel.applyEvent(event);
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
                "wallpaper": wallpaperComponent
            })
            Component {
                id: quickSettingsComponent
                ControlCenter.ControlCentre {
                    screen: morphSurface.screen
                    noxd: daemonClient; audio: audioModel; brightness: brightnessModel
                    network: networkModel; bluetooth: bluetoothModel; battery: batteryModel
                    power: powerModel; hyprland: hyprlandModel; systemModel: systemModel
                }
            }
            Component {
                id: calendarComponent
                CalendarSurface.CalendarWidget { screen: morphSurface.screen; noxd: daemonClient; calModel: calendarModel }
            }
            Component {
                id: notificationComponent
                NotificationSurfaces.NotificationCentre { screen: morphSurface.screen; noxd: daemonClient; notifModel: notificationModel; morphRegistry: morphRegistry }
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
            Component.onCompleted: {
                panelController.registerPanel("quick-settings", this);
                panelController.registerPanel("calendar", this);
                panelController.registerPanel("notifications", this);
                panelController.registerPanel("media", this);
                panelController.registerPanel("clipboard", this);
                panelController.registerPanel("wallpaper", this);
                surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typePanel);
            }
            Component.onDestruction: {
                surfaceCoordinatorInstance.unregister(this);
            }
        }
    }

    // ── Quick Share (left-side activity panel, per-screen) ──
    // Coexists with right-side island states (design contract §3.2).
    Variants {
        model: Quickshell.screens
        ShareSurface.QuickSharePanel {
            required property var modelData
            screen: modelData
            noxd: daemonClient
            transfer: transferModel
            Component.onCompleted: {
                panelController.registerPanel("quick-share", this);
                surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typePanel);
            }
            Component.onDestruction: {
                surfaceCoordinatorInstance.unregister(this);
            }
        }
    }

    function toggleControlCentre() { panelController.toggle("quick-settings"); }
    function openControl()   { panelController.open("quick-settings"); }
    function closeControl()  { panelController.close("quick-settings"); }

    function toggleNotificationCentre() { panelController.toggle("notifications"); }
    function openNotifications()   { panelController.open("notifications"); }
    function closeNotifications()  { panelController.close("notifications"); }

    function toggleCalendar() { panelController.toggle("calendar"); }
    function openCalendar()   { panelController.open("calendar"); }
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

    // ── Radial Wheel (per-screen panel via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        RadialSurface.RadialWheel {
            required property var modelData
            screen: modelData
            noxd: daemonClient
            Component.onCompleted: {
                rwTracker.add(modelData, this);
                surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typePanel);
            }
            Component.onDestruction: {
                rwTracker.remove(modelData);
                surfaceCoordinatorInstance.unregister(this);
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
        audio: audioModel; battery: batteryModel; network: networkModel
        calModel: calendarModel
        weatherModel: weatherModel
        systemModel: systemModel
        screen: Quickshell.activeScreen || null
        onRequestCaptureAfterClose: shellRoot.openCapture()
        Component.onCompleted: surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typeModal)
        Component.onDestruction: surfaceCoordinatorInstance.unregister(this)
    }
    function toggleDashboard() { dashboard.toggle(); }
    function openDashboard()   { dashboard.open(); }
    function closeDashboard()  { dashboard.close(); }

    // ── Settings Panel (modal, singleton) ──
    SettingsSurface.SettingsPanel {
        id: settingsPanel
        noxd: daemonClient
        screen: Quickshell.activeScreen || null
        Component.onCompleted: surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typeModal)
        Component.onDestruction: surfaceCoordinatorInstance.unregister(this)
    }
    function toggleSettings() { settingsPanel.toggle(); }
    function openSettings()   { settingsPanel.open(); }
    function closeSettings()  { settingsPanel.close(); }

    // ── DND / Night Light (IPC convenience) ──
    property Process dndToggle: Process { command: ["dunstctl", "toggle"]; running: false }
    property Process nightLightToggle: Process { command: ["sh", "-c", "if command -v hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset identity 2>/dev/null || hyprsunset -t 4500; fi"]; running: false }
    function toggleDnd() { dndToggle.running = true; }
    function toggleNightLight() { nightLightToggle.running = true; }

    // ── Capture overlay (modal, singleton) ──
    CaptureSurface.Capture {
        id: capture
        noxd: daemonClient
        screen: Quickshell.activeScreen || null
        onFullScreenCaptureRequested: dest => {
            captureFullScreen.command = ["sh", "-c", "mkdir -p \"$(dirname '" + dest.replace(/'/g, "'\\''") + "')\" && grim \"" + dest.replace(/'/g, "'\\''") + "\" && notify-send 'Screenshot saved' \"" + dest.replace(/'/g, "'\\''") + "\" -t 3000 || notify-send 'Screenshot failed' 'grim returned an error' -u critical"];
            captureFullScreen.running = true;
        }
        Component.onCompleted: surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typeModal)
        Component.onDestruction: surfaceCoordinatorInstance.unregister(this)
    }
    property Process captureFullScreen: Process { running: false }
    function toggleCapture() { capture.toggle(); }
    function openCapture()   { capture.open(); }
    function closeCapture()  { capture.close(); }

    // ── Universal Launcher (modal, singleton, full-screen overlay) ──
    LauncherSurface.Launcher {
        id: launcher
        noxd: daemonClient; hyprland: hyprlandModel
        clipboardModel: clipboardModel
        screen: Quickshell.activeScreen || null
        onRequestCaptureAfterClose: shellRoot.openCapture()
        Component.onCompleted: surfaceCoordinatorInstance.register(this, surfaceCoordinatorInstance.typeModal)
        Component.onDestruction: surfaceCoordinatorInstance.unregister(this)
    }
    function toggleLauncher() { launcher.toggle(); }
    function openLauncher()   { launcher.open(); }
    function closeLauncher()  { launcher.close(); }

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
        function openCapture()   { shellRoot.capture.open(); }
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
        function handleEscape()     { return shellRoot.surfaceCoordinator ? shellRoot.surfaceCoordinator.handleEscape() : false; }
        function toggleQuickSettingsPanel() { return shellRoot.toggleControlCentre(); }
        function openQuickSettingsPanel()   { return shellRoot.openControl(); }
        function toggleMediaPanelFromIpc()  { return shellRoot.toggleMediaPanel(); }
        function openMediaPanelFromIpc()    { return shellRoot.openMediaPanel(); }
        function toggleClipboardPanel() { return shellRoot.toggleClipboardPanel(); }
        function openClipboardPanel()   { return shellRoot.openClipboardPanel(); }
        function toggleSharePanel() { return shellRoot.toggleSharePanel(); }
        function openSharePanel()   { return shellRoot.openSharePanel(); }
        function toggleWallpaperPanel() { return shellRoot.toggleWallpaperPanel(); }
        function openWallpaperPanel()   { return shellRoot.openWallpaperPanel(); }
        function closePanel()       { return shellRoot.coordinator.close(); }
        function panelState()       { return { activePanel: shellRoot.coordinator.activePanel, state: shellRoot.coordinator.state }; }
    }

    // ── NoxIsland (per-screen) ──
    Variants {
        model: Quickshell.screens
        NoxIsland {
            required property var modelData
            noxd: daemonClient; audio: audioModel; brightness: brightnessModel
            screen: modelData
        }
    }

    // ── Bar (per-screen) ──
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            noxd: daemonClient; hyprland: hyprlandModel; audio: audioModel
            battery: batteryModel; network: networkModel; bluetooth: bluetoothModel; media: mediaModel
            notificationModel: notificationModel
            systemModel: systemModel
            screen: modelData
        }
    }
}
