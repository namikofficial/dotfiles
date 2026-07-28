import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../config" as Config

// The only major-panel PanelWindow. Content views are ordinary Items loaded
// into this window, so geometry and input ownership never change during a
// panel switch.
PanelWindow {
    id: root
    required property var screen
    required property var panelComponents
    property string activePanel: ""
    property string pendingPanel: ""
    property rect originRect: Qt.rect(0, 0, 0, 0)
    property bool active: activePanel !== "" || pendingPanel !== ""
    property real topMargin: targetTopMargin
    property real rightMargin: targetRightMargin
    property real surfaceWidth: targetWidth
    property real surfaceHeight: targetHeight
    readonly property real targetTopMargin: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingSm)
    readonly property real targetRightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    readonly property real targetBottomMargin: Theme.Tokens.scaled(Theme.Tokens.spacingLg)
    readonly property real targetWidth: activePanel === "calendar" ? Theme.Tokens.scaled(520) : Theme.Tokens.scaled(380)
    readonly property real targetHeight: activePanel === "media" ? Theme.Tokens.scaled(230) :
        (activePanel === "calendar" ? Theme.Tokens.scaled(650) : (screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700)))
    readonly property int morphDuration: Config.Motion.panelOpen
    property bool switching: pendingPanel !== ""

    screen: root.screen
    anchors.top: true; anchors.right: true
    margins.top: topMargin; margins.right: rightMargin
    implicitWidth: surfaceWidth; implicitHeight: surfaceHeight
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: root.active

    Behavior on topMargin { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on rightMargin { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on surfaceWidth { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on surfaceHeight { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }

    Loader {
        id: content
        anchors.fill: parent
        active: root.activePanel !== ""
        sourceComponent: root.panelComponents && root.activePanel
            ? (root.panelComponents[root.activePanel] || null) : null
        onLoaded: {
            if (item && typeof item.open === "function") item.open();
        }
    }

    Timer {
        id: replaceTimer
        interval: Math.max(1, Math.round(root.morphDuration * 0.52))
        repeat: false
        onTriggered: {
            root.activePanel = root.pendingPanel;
            root.pendingPanel = "";
        }
    }

    Timer {
        id: closeTimer
        interval: root.morphDuration
        repeat: false
        onTriggered: {
            root.activePanel = "";
            root.pendingPanel = "";
        }
    }

    function componentFor(name) { return root.panelComponents ? (root.panelComponents[name] || null) : null; }

    function geometryFor(name, rect) {
        var width = name === "calendar" ? Theme.Tokens.scaled(520) : Theme.Tokens.scaled(380);
        var height = name === "media" ? Theme.Tokens.scaled(230) :
            (name === "calendar" ? Theme.Tokens.scaled(650) : (screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700)));
        var hasOrigin = rect && rect.width > 0 && rect.height > 0;
        if (hasOrigin) return { top: Math.max(0, rect.y), right: Math.max(0, screen.width - rect.x - rect.width), width: rect.width, height: rect.height };
        return { top: targetTopMargin, right: targetRightMargin, width: width, height: height };
    }

    function moveToTarget(name) {
        var g = geometryFor(name, null);
        topMargin = g.top; rightMargin = g.right; surfaceWidth = g.width; surfaceHeight = g.height;
        Qt.callLater(function() { topMargin = targetTopMargin; rightMargin = targetRightMargin; surfaceWidth = g.width; surfaceHeight = g.height; });
    }

    function openPanel(name, rect) {
        if (!componentFor(name)) return false;
        closeTimer.stop();
        if (rect && rect.width > 0 && rect.height > 0) originRect = rect;
        var g = geometryFor(name, rect);
        if (activePanel === name && pendingPanel === "") { closePanel(); return true; }
        if (activePanel !== "" && activePanel !== name) {
            pendingPanel = name;
            topMargin = targetTopMargin; rightMargin = targetRightMargin;
            surfaceWidth = g.width; surfaceHeight = g.height;
            replaceTimer.restart();
            return true;
        }
        activePanel = name;
        topMargin = g.top; rightMargin = g.right; surfaceWidth = g.width; surfaceHeight = g.height;
        content.active = true;
        moveToTarget(name);
        return true;
    }

    function closePanel() {
        if (!activePanel && !pendingPanel) return false;
        replaceTimer.stop(); pendingPanel = "";
        var g = geometryFor(activePanel || "quick-settings", originRect);
        topMargin = g.top; rightMargin = g.right; surfaceWidth = g.width; surfaceHeight = g.height;
        closeTimer.restart();
        return true;
    }

    function open() { if (activePanel) openPanel(activePanel, originRect); }
    function close() { closePanel(); }
}
