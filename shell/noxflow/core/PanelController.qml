import QtQml
import Quickshell

// One owner for all major interactive surfaces. Individual surfaces retain
// their existing implementations, but cannot be open concurrently.
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
        state = PanelController.State.Hidden;
    }
}
