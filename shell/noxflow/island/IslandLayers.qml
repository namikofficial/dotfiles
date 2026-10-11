import QtQuick
import "../theme" as Theme
import "../surfaces/calendar" as CalendarSurface

// IslandLayers.qml — the island's two overlay layers.
//
// The inline calendar and the launcher are both "a big surface hosted inside
// the island's slot". They shared a close/open lifecycle with the host but had
// no other reason to live in the host file.
//
// Decision 6 also applies here: Escape closes the active layer, and the
// calendar and launcher are mutually exclusive — opening one closes the other.



Item {
    id: root

    // ── Inputs ──
    property var screen: null
    property var noxd: null
    property var calModel: null
    property var launcherComponent: null
    property var activityController: null
    required property Item host
    property real calendarHeight: Theme.Tokens.scaled(650)

    // ── State ──
    property bool calendarExpanded: false
    property bool launcherOpen: false
    property bool launcherClosing: false
    property bool launcherWasVisible: false
    readonly property bool launcherVisible: launcherOpen || launcherClosing

    /// The inline calendar item, so the host can alias it into the top-chrome
    /// input mask (the calendar sits outside the island card).
    property alias calendarHostItem: calendarHost

    signal focusRequested()
    signal layerClosed()

    // ── Inline calendar ──
    Item {
        id: calendarHost
        visible: root.calendarExpanded
        z: 20
        width: Math.min(parent.width - Theme.Tokens.scaled(24), Theme.Tokens.scaled(Theme.Tokens.islandCalendarWidth))
        height: root.calendarHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        CalendarSurface.CalendarWidget {
            id: calendarWidget
            anchors.fill: parent
            screen: root.screen
            noxd: root.noxd
            calModel: root.calModel
        }
        Connections {
            target: calendarWidget
            function onVisibleChanged() {
                if (!calendarWidget.visible) root.calendarExpanded = false;
            }
        }
    }

    // ── Launcher ──
    // Sized to the island card (IslandCard.qml uses the same width formula),
    // not to this layer: the layer spans the whole bar window, so `fill`
    // spread the launcher's field, tabs and list across the full screen
    // width while the card behind it sat empty in the middle.
    Loader {
        id: launcherLoader
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: Theme.Tokens.spacingLg
        width: Math.min(parent.width - Theme.Tokens.scaled(24), Theme.Tokens.scaled(Theme.Tokens.islandLauncherWidth))
            - 2 * Theme.Tokens.spacingLg
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
            else if (root.launcherWasVisible) root.finishClose();
        }
    }

    // ── Control ──
    function openCalendar() {
        if (root.launcherVisible) root.closeLauncher();
        root.calendarExpanded = true;
        root.activityController.openLayer("calendar", root.screen && root.screen.name ? root.screen.name : "");
        // CalendarWidget keeps its own SurfaceLifecycle: `visible` is
        // `lifecycle.active` and its body is `opacity: openProgress`, both 0
        // until something calls open(). The pre-split NoxIsland did that from
        // here; when these two functions moved into IslandLayers the calls were
        // left behind, so the calendar's container was visible and measured
        // while the widget inside it stayed invisible and fully transparent.
        if (calendarWidget && typeof calendarWidget.open === "function") calendarWidget.open();
    }

    function closeCalendar() {
        if (!root.calendarExpanded) return;
        root.calendarExpanded = false;
        root.activityController.closeLayer();
        if (calendarWidget && typeof calendarWidget.close === "function") calendarWidget.close();
    }

    function openLauncher() {
        if (root.launcherOpen) return;
        if (root.calendarExpanded) root.closeCalendar();
        root.launcherWasVisible = false;
        root.launcherClosing = false;
        root.launcherOpen = true;
        root.activityController.openLayer("launcher", root.screen && root.screen.name ? root.screen.name : "");
        root.focusRequested();
    }

    /// Ask the launcher to close itself. It animates, so the host waits for
    /// the item's visible change before finalising.
    function closeLauncher() {
        if (!root.launcherVisible) return;
        root.launcherClosing = true;
        if (launcherLoader.item && typeof launcherLoader.item.close === "function")
            launcherLoader.item.close();
        else root.finishClose();
    }

    function finishClose() {
        root.launcherWasVisible = false;
        root.launcherClosing = false;
        root.launcherOpen = false;
        root.activityController.closeLayer();
        root.layerClosed();
    }

    function toggleLauncher() {
        if (root.launcherVisible) root.closeLauncher();
        else root.openLauncher();
    }
}