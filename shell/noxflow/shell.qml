import QtQuick
import Quickshell
import Quickshell.Io
import "surfaces/controlcenter" as ControlCenter
import "surfaces/notifications" as NotificationSurfaces
import "surfaces/launcher" as LauncherSurface
import "surfaces/overview" as OverviewSurface
import "surfaces/capture" as CaptureSurface
import "surfaces/radialmenu" as RadialSurface
import "surfaces/calendar" as CalendarSurface
import "surfaces/dashboard" as DashboardSurface
import "surfaces/settings" as SettingsSurface

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
    MorphRegistry { id: morphRegistry }
    WeatherModel { id: weatherModel; Component.onCompleted: start() }
    SystemModel { id: systemModel; Component.onCompleted: start() }
    CaptureSurface.QuickSnipSettings { id: quickSnipSettings; Component.onCompleted: load() }

    // ── Per-screen instance trackers ──
    InstanceTracker { id: ccTracker }
    InstanceTracker { id: ncTracker }
    InstanceTracker { id: calTracker }
    InstanceTracker { id: rwTracker }

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
            }
        }
    }

    // ── Control Centre (per-screen via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        ControlCenter.ControlCentre {
            required property var modelData
            screen: modelData
            noxd: daemonClient; audio: audioModel; brightness: brightnessModel
            network: networkModel; bluetooth: bluetoothModel; battery: batteryModel
            power: powerModel; hyprland: hyprlandModel
            Component.onCompleted: ccTracker.add(modelData, this)
            Component.onDestruction: ccTracker.remove(modelData)
        }
    }
    function toggleControlCentre() { ccTracker.toggle(); }
    function openControl()   { var c = ccTracker.forScreen(null); if (c) c.open(); }
    function closeControl()  { var c = ccTracker.forScreen(null); if (c) c.close(); }

    // ── Notification Centre (per-screen via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        NotificationSurfaces.NotificationCentre {
            required property var modelData
            screen: modelData
            noxd: daemonClient
            notifModel: notificationModel
            morphRegistry: morphRegistry
            Component.onCompleted: ncTracker.add(modelData, this)
            Component.onDestruction: ncTracker.remove(modelData)
        }
    }
    function toggleNotificationCentre() { ncTracker.toggle(); }
    function openNotifications()   { var n = ncTracker.forScreen(null); if (n) n.open(); }
    function closeNotifications()  { var n = ncTracker.forScreen(null); if (n) n.close(); }

    // ── Calendar Widget (per-screen via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        CalendarSurface.CalendarWidget {
            required property var modelData
            screen: modelData
            noxd: daemonClient; calModel: calendarModel
            Component.onCompleted: calTracker.add(modelData, this)
            Component.onDestruction: calTracker.remove(modelData)
        }
    }
    function toggleCalendar() { calTracker.toggle(); }
    function openCalendar()   { var c = calTracker.forScreen(null); if (c) c.open(); }
    function closeCalendar()  { var c = calTracker.forScreen(null); if (c) c.close(); }

    // ── Radial Wheel (per-screen via InstanceTracker) ──
    Variants {
        model: Quickshell.screens
        RadialSurface.RadialWheel {
            required property var modelData
            screen: modelData
            noxd: daemonClient
            Component.onCompleted: rwTracker.add(modelData, this)
            Component.onDestruction: rwTracker.remove(modelData)
        }
    }
    function toggleRadialWheel() { rwTracker.toggle(); }
    function openRadialWheel()   { var r = rwTracker.forScreen(null); if (r) r.open(); }
    function closeRadialWheel()  { var r = rwTracker.forScreen(null); if (r) r.close(); }

    // ── Dashboard (full-screen, singleton) ──
    DashboardSurface.Dashboard {
        id: dashboard
        noxd: daemonClient; hyprland: hyprlandModel
        audio: audioModel; battery: batteryModel; network: networkModel
        calModel: calendarModel
        weatherModel: weatherModel
        systemModel: systemModel
        screen: Quickshell.activeScreen || null
    }
    function toggleDashboard() { dashboard.toggle(); }
    function openDashboard()   { dashboard.open(); }
    function closeDashboard()  { dashboard.close(); }

    // ── Settings Panel (singleton) ──
    SettingsSurface.SettingsPanel {
        id: settingsPanel
        noxd: daemonClient
        screen: Quickshell.activeScreen || null
    }
    function toggleSettings() { settingsPanel.toggle(); }
    function openSettings()   { settingsPanel.open(); }

    // ── DND / Night Light (IPC convenience) ──
    property Process dndToggle: Process { command: ["dunstctl", "toggle"]; running: false }
    property Process nightLightToggle: Process { command: ["sh", "-c", "if command -v hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset identity 2>/dev/null || hyprsunset -t 4500; fi"]; running: false }
    function toggleDnd() { dndToggle.running = true; }
    function toggleNightLight() { nightLightToggle.running = true; }

    // ── Capture overlay (singleton) ──
    CaptureSurface.Capture {
        id: capture
        noxd: daemonClient
        screen: Quickshell.activeScreen || null
    }
    function toggleCapture() { capture.toggle(); }
    function openCapture()   { capture.open(); }

    // ── Universal Launcher (singleton, full-screen overlay) ──
    LauncherSurface.Launcher {
        id: launcher
        noxd: daemonClient; hyprland: hyprlandModel
        clipboardModel: clipboardModel
        screen: Quickshell.activeScreen || null
    }
    function toggleLauncher() { launcher.toggle(); }
    function openLauncher()   { launcher.open(); }

    // ── Workspace Overview (singleton) ──
    OverviewSurface.Overview {
        id: overview
        noxd: daemonClient; hyprland: hyprlandModel
        screen: Quickshell.activeScreen || null
    }
    function toggleOverview() { overview.toggle(); }
    function openOverview()   { overview.open(); }

    // ── Global IPC handler for external keybind control ──
    IpcHandler {
        target: "noxctl"
        function toggleControl() { shellRoot.toggleControlCentre(); }
        function openControl()    { var cc = shellRoot.ccTracker.forScreen(null); if (cc) cc.open(); }
        function closeControl()   { var cc = shellRoot.ccTracker.forScreen(null); if (cc) cc.close(); }
        function toggleNotifications() { shellRoot.toggleNotificationCentre(); }
        function openNotifications()   { var nc = shellRoot.ncTracker.forScreen(null); if (nc) nc.open(); }
        function closeNotifications()  { var nc = shellRoot.ncTracker.forScreen(null); if (nc) nc.close(); }
        function toggleRadialWheel() { shellRoot.toggleRadialWheel(); }
        function openRadialWheel()   { var rw = shellRoot.rwTracker.forScreen(null); if (rw) rw.open(); }
        function closeRadialWheel()  { var rw = shellRoot.rwTracker.forScreen(null); if (rw) rw.close(); }
        function toggleLauncher() { shellRoot.toggleLauncher(); }
        function openLauncher()   { shellRoot.openLauncher(); }
        function toggleOverview() { shellRoot.toggleOverview(); }
        function openOverview()   { shellRoot.openOverview(); }
        function toggleCapture() { shellRoot.toggleCapture(); }
        function openCapture()   { shellRoot.capture.open(); }
        function toggleCalendar() { shellRoot.toggleCalendar(); }
        function openCalendar()   { var cal = shellRoot.calTracker.forScreen(null); if (cal) cal.open(); }
        function closeCalendar()  { var cal = shellRoot.calTracker.forScreen(null); if (cal) cal.close(); }
        function toggleDashboard() { shellRoot.toggleDashboard(); }
        function openDashboard()   { shellRoot.openDashboard(); }
        function closeDashboard()  { shellRoot.dashboard.close(); }
        function toggleSettings() { shellRoot.toggleSettings(); }
        function openSettings()   { shellRoot.openSettings(); }
        function toggleDnd()      { shellRoot.toggleDnd(); }
        function toggleNightLight() { shellRoot.toggleNightLight(); }
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
