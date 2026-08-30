import QtQml
import Quickshell

// One owner for all major interactive surfaces. Individual surfaces retain
// their existing implementations, but cannot be open concurrently.
//
// This is the REQUEST layer of the shell state machine. It owns:
//   - semantic requested state (what the user asked for)
//   - per-screen targeting (which monitor owns the trigger chip)
//   - retargeting on rapid toggles (never queues; always retargets)
//
// The EXECUTION layer is MorphSurface (per-screen PanelWindow) which owns the
// mounted/visible/interactive/transitioning phases and the geometry morph.
// PanelController only records intent and asks the right MorphSurface to act.
QtObject {
    id: root
    enum State { Hidden, Opening, Open, Switching, Closing }
    property int state: PanelController.State.Hidden
    property string activePanel: ""
    property string previousPanel: ""
    property string targetMonitor: ""
    property rect originRect: Qt.rect(0, 0, 0, 0)
    property var triggerRegistry: null
    property bool isInteractive: false
    property bool isAnimating: false
    property var panels: ({})
    signal panelChanged(string panel, string previous)

    // ── Semantic state model (design contract §2) ──
    readonly property string stateIdle: "idle"
    readonly property string stateMedia: "media"
    readonly property string stateCalendar: "calendar"
    readonly property string stateControlCenter: "control-center"
    readonly property string stateNotifications: "notifications"
    readonly property string stateSystem: "system"
    readonly property string stateWallpaper: "wallpaper"
    readonly property string stateClipboard: "clipboard"
    readonly property string stateShare: "share"

    // The semantic state the user requested. Maps to a registered panel name
    // via panelForState(). "idle" means no expanded surface.
    property string requestedState: stateIdle
    // The semantic state currently being displayed (may lag requestedState
    // during a transition).
    property string visualState: stateIdle

    // Panels that map to semantic states. Quick-share is a left-side panel
    // that may coexist with a right-side island state; it is registered
    // separately and not exclusive.
    property var statePanels: ({
        "media": "media",
        "calendar": "calendar",
        "control-center": "quick-settings",
        "notifications": "notifications",
        "system": "system-monitor",
        "wallpaper": "wallpaper",
        "clipboard": "clipboard",
        "share": "quick-share"
    })

    function panelForState(stateName) {
        return root.statePanels[stateName] || "";
    }

    function stateForPanel(panelName) {
        for (var stateName in root.statePanels) {
            if (root.statePanels[stateName] === panelName) return stateName;
        }
        return root.stateIdle;
    }

    function registerPanel(name, surface) {
        var next = {};
        for (var key in panels) next[key] = panels[key];
        var list = (next[name] || []).slice();
        if (list.indexOf(surface) < 0) list.push(surface);
        next[name] = list;
        panels = next;
    }

    function surface(name) {
        var list = panels[name] || [];
        var active = targetMonitor ? null : Quickshell.activeScreen;
        for (var i = 0; i < list.length; i++) {
            if (targetMonitor && list[i].screen && list[i].screen.name === targetMonitor) return list[i];
            if (active && list[i].screen === active) return list[i];
        }
        return list.length ? list[0] : null;
    }

    function closeSurface(name) {
        var list = panels[name] || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i].closePanel === "function") list[i].closePanel();
            else if (list[i] && typeof list[i].close === "function") list[i].close();
        }
    }

    function setRequested(stateName) {
        root.requestedState = stateName;
        root.visualState = stateName;
    }

    function open(name, monitorName, sourceRect, initialSection) {
        targetMonitor = monitorName || (Quickshell.activeScreen ? Quickshell.activeScreen.name : "");
        var registered = triggerRegistry && typeof triggerRegistry.trigger === "function"
            ? triggerRegistry.trigger(name, targetMonitor) : null;
        if (!surface(name)) return false;
        if (activePanel === name) {
            if (initialSection && initialSection !== "") {
                var same = surface(name);
                if (same && typeof same.openPanel === "function") same.openPanel(name, originRect, initialSection);
                return true;
            }
            close(name); return true;
        }
        var old = activePanel;
        previousPanel = old;
        originRect = sourceRect || (registered ? Qt.rect(registered.globalX, registered.globalY, registered.globalWidth, registered.globalHeight) : Qt.rect(0, 0, 0, 0));
        state = old ? PanelController.State.Switching : PanelController.State.Opening;
        isAnimating = true;
        for (var key in panels) if (key !== name) closeSurface(key);
        activePanel = name;
        setRequested(stateForPanel(name));
        var next = surface(name);
        if (next && typeof next.openPanel === "function") next.openPanel(name, originRect, initialSection || "");
        else if (next && typeof next.open === "function") next.open();
        isInteractive = true;
        isAnimating = false;
        state = PanelController.State.Open;
        panelChanged(name, old);
        return true;
    }

    function toggle(name, monitorName, sourceRect, initialSection) { return open(name, monitorName, sourceRect, initialSection); }

    function close(name) {
        var requested = name || activePanel;
        if (!requested) return false;
        closeSurface(requested);
        previousPanel = requested;
        activePanel = "";
        isInteractive = false;
        isAnimating = false;
        setRequested(stateIdle);
        state = PanelController.State.Hidden;
        panelChanged("", requested);
        return true;
    }

    function closeAll() {
        for (var key in panels) closeSurface(key);
        activePanel = "";
        previousPanel = "";
        isInteractive = false;
        isAnimating = false;
        setRequested(stateIdle);
        state = PanelController.State.Hidden;
    }

    // Keep controller state synchronized when a child surface closes itself.
    function surfaceClosed(name, instance) {
        if (activePanel !== name) return;
        if (instance && surface(name) !== instance) return;
        previousPanel = name;
        activePanel = "";
        isInteractive = false;
        isAnimating = false;
        setRequested(stateIdle);
        state = PanelController.State.Hidden;
        panelChanged("", name);
    }
}
