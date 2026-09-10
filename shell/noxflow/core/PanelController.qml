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

    // Defensive: detect QML object references whose underlying C++ object was
    // destroyed. Accessing .objectName / metaObject on such an instance throws
    // "ReferenceError: <name> is destroyed". We probe an always-required
    // property — screen — which Quickshell nulls when the underlying window
    // is destroyed, and fall back to a try/catch for any other destruction
    // signals. Returns true for null/undefined as well.
    function isDestroyed(instance) {
        if (!instance) return true;
        try {
            var probe = instance.screen;
            return probe === undefined || probe === null;
        } catch (error) {
            return true;
        }
    }

    function registerPanel(name, surface) {
        var next = {};
        for (var key in panels) next[key] = panels[key];
        var list = (next[name] || []).slice();
        if (list.indexOf(surface) < 0) {
            list.push(surface);
            next[name] = list;
        }
        panels = next;
    }

    // Remove a previously-registered surface from the registry. Called by the
    // surface in its own Component.onDestruction so the controller does not
    // retain stale references after a monitor disconnects or the shell shuts
    // down. If the destroyed surface was the active instance for its panel,
    // the controller transitions out of the active state so a subsequent
    // open() on a surviving monitor can proceed without leaking state.
    function unregisterPanel(name, surface) {
        var list = panels[name];
        if (!list) return false;
        var idx = list.indexOf(surface);
        if (idx < 0) return false;
        var nextList = list.slice();
        nextList.splice(idx, 1);
        var next = {};
        for (var key in panels) next[key] = panels[key];
        if (nextList.length === 0) {
            delete next[name];
        } else {
            next[name] = nextList;
        }
        panels = next;
        if (activePanel === name) {
            previousPanel = name;
            activePanel = "";
            isInteractive = false;
            isAnimating = false;
            setRequested(stateIdle);
            state = PanelController.State.Hidden;
            panelChanged("", name);
        }
        return true;
    }

    // Drop every destroyed entry from the registry. Used by callers that
    // hold a snapshot (e.g. surface()) and need a safe iteration.
    function pruneDestroyed() {
        var changed = false;
        var next = {};
        for (var key in panels) {
            var list = panels[key];
            var kept = [];
            for (var i = 0; i < list.length; i++) {
                if (isDestroyed(list[i])) {
                    changed = true;
                    continue;
                }
                kept.push(list[i]);
            }
            if (kept.length > 0) next[key] = kept;
            else if (list.length > 0) changed = true;
        }
        if (changed) panels = next;
        return changed;
    }

    function surface(name) {
        var list = panels[name] || [];
        var active = targetMonitor ? null : Quickshell.activeScreen;
        for (var i = 0; i < list.length; i++) {
            var inst = list[i];
            if (isDestroyed(inst)) continue;
            if (targetMonitor && inst.screen && inst.screen.name === targetMonitor) return inst;
            if (active && inst.screen === active) return inst;
        }
        // Fallback: any live instance if monitor targeting didn't match.
        for (var j = 0; j < list.length; j++) {
            if (!isDestroyed(list[j])) return list[j];
        }
        return null;
    }

    function closeSurface(name) {
        var list = panels[name] || [];
        for (var i = 0; i < list.length; i++) {
            var inst = list[i];
            if (isDestroyed(inst)) continue;
            if (inst && typeof inst.closePanel === "function") inst.closePanel();
            else if (inst && typeof inst.close === "function") inst.close();
        }
    }

    function setRequested(stateName) {
        root.requestedState = stateName;
        root.visualState = stateName;
    }

    function open(name, monitorName, sourceRect, initialSection) {
        targetMonitor = monitorName || (Quickshell.activeScreen ? Quickshell.activeScreen.name : "");
        // Drop any destroyed entries left behind by a prior monitor disconnect.
        pruneDestroyed();
        var list = panels[name];
        if (!list || list.length === 0) return false;
        var registered = triggerRegistry && typeof triggerRegistry.trigger === "function"
            ? triggerRegistry.trigger(name, targetMonitor) : null;
        var target = surface(name);
        if (!target) return false;

        // Idempotent re-open on the same monitor: the panel stays open.
        // An explicit initialSection retargets without closing (used by
        // deep-links such as open("quick-settings", "", null, "network")).
        if (activePanel === name && surface(name) === target) {
            if (initialSection && initialSection !== "" && typeof target.openPanel === "function") {
                target.openPanel(name, originRect, initialSection);
            }
            return true;
        }

        var old = activePanel;
        previousPanel = old;
        originRect = sourceRect || (registered ? Qt.rect(registered.globalX, registered.globalY, registered.globalWidth, registered.globalHeight) : Qt.rect(0, 0, 0, 0));
        state = old ? PanelController.State.Switching : PanelController.State.Opening;
        isAnimating = true;
        for (var key in panels) if (key !== name) closeSurface(key);
        activePanel = name;
        setRequested(stateForPanel(name));
        if (typeof target.openPanel === "function") target.openPanel(name, originRect, initialSection || "");
        else if (typeof target.open === "function") target.open();
        isInteractive = true;
        isAnimating = false;
        state = PanelController.State.Open;
        panelChanged(name, old);
        return true;
    }

    // toggle is intentionally distinct from open: opening an active panel is
    // the only way to close it from outside the surface (Escape and the
    // surface's own close button delegate through the surface itself, not
    // through PanelController).
    function toggle(name, monitorName, sourceRect, initialSection) {
        if (activePanel === name && surface(name)) {
            return close(name);
        }
        return open(name, monitorName, sourceRect, initialSection);
    }

    // close is name-safe: it only mutates the active state when the panel
    // being closed is actually the active one. Calling close("B") while A is
    // active must NOT clear activePanel — A remains visible.
    function close(name) {
        var requested = name || activePanel;
        if (!requested) return false;

        if (requested !== activePanel) {
            // Closing an inactive panel: just run the surface close path so
            // a stuck or pending surface gets torn down. Leave active state
            // intact because the user did not ask to dismiss whatever panel
            // is currently visible.
            closeSurface(requested);
            return true;
        }

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
    // Generation-safe: destroyed surfaces are skipped (otherwise the strict
    // equality check below would dereference a dead reference and throw).
    function surfaceClosed(name, instance) {
        if (activePanel !== name) return;
        if (instance && isDestroyed(instance)) return;
        if (instance) {
            var current = surface(name);
            // Only honor the close for the surface that actually reported it.
            // Other live instances of the same panel keep the controller state
            // aligned with the still-visible window.
            if (current && current !== instance) return;
        }
        previousPanel = name;
        activePanel = "";
        isInteractive = false;
        isAnimating = false;
        setRequested(stateIdle);
        state = PanelController.State.Hidden;
        panelChanged("", name);
    }
}
