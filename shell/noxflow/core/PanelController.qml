import QtQml
import Quickshell
import "SurfaceStack.js" as Stack

// PanelController — the single owner for every interactive surface.
//
// It is the REQUEST layer of the shell state machine. It owns:
//   - semantic requested state (what the user asked for)
//   - per-screen targeting (which monitor owns the trigger chip)
//   - retargeting on rapid toggles (never queues; always retargets)
//   - the modal stack and Escape routing
//
// The EXECUTION layer is MorphSurface (per-screen PanelWindow) which owns the
// mounted/visible/interactive/transitioning phases and the geometry morph.
// PanelController only records intent and asks the right MorphSurface to act.
//
// ── Why SurfaceCoordinator is gone ──
// It used to be a second, independent coordinator that tracked modals and
// panels purely so Escape had something to route to. Two registries describing
// the same surfaces could not see each other, which is how the rules below came
// to contradict each other: PanelController closed every other panel when one
// opened, while SurfaceCoordinator's own contract said panels "may coexist with
// each other and with modals", and Escape went wherever that second list
// happened to point. One list, one rule: at most one panel, modals stack, and
// Escape always closes the topmost thing.
QtObject {
    id: root

    // Hidden/Open is all any caller can observe. Opening, Switching and Closing
    // used to exist but were assigned and overwritten inside a single
    // synchronous call, so nothing could ever read them: the real transition is
    // owned by MorphSurface, which reports back through panelClosed().
    enum State { Hidden, Open }
    property int state: PanelController.State.Hidden
    property string activePanel: ""
    property string previousPanel: ""
    property string targetMonitor: ""
    property rect originRect: Qt.rect(0, 0, 0, 0)
    property var triggerRegistry: null
    property bool isInteractive: false
    property var panels: ({})
    signal panelChanged(string panel, string previous)

    // ── Modal stack ──
    // Exclusive full-screen overlays (Dashboard, Overview, Launcher, Capture,
    // Settings). Ordered oldest-first; the last entry is on top. Modals are not
    // in `panels`: a modal is not a side panel and must not be closed by
    // `open()` sweeping the panel registry.
    property var modals: []

    function registerModal(surface) { modals = Stack.push(modals, surface); }

    function unregisterModal(surface) { modals = Stack.remove(modals, surface); }

    // Every modal stays registered for the shell's lifetime, so registration is
    // not "on screen". A hidden modal must be skipped like a destroyed one:
    // otherwise the last-registered (hidden) modal is always "topmost", Escape
    // closes nothing, and the open panel underneath never gets the key.
    function isInactiveModal(surface) {
        if (!surface) return true;
        try { return surface.visible !== true; } catch (error) { return true; }
    }

    function topmostModal() { return Stack.topmost(modals, isInactiveModal); }

    function isTopmostModal(surface) {
        return topmostModal() === surface;
    }

    function closeModals(except) {
        for (var i = 0; i < modals.length; i++) {
            var m = modals[i];
            if (m === except || isInactiveModal(m)) continue;
            if (typeof m.close === "function") m.close();
        }
    }

    /// Open the given modal alone: every other visible modal and the active
    /// panel close first, so overlays never stack.
    function openModal(surface) {
        if (!surface) return;
        closeModals(surface);
        if (activePanel) close(activePanel);
        modals = Stack.push(modals, surface); // most recently opened is on top
        if (typeof surface.open === "function") surface.open();
    }

    function toggleModal(surface) {
        if (!surface) return;
        if (isInactiveModal(surface)) { openModal(surface); return; }
        // Still visible: open, or mid-close animation. The surface's own
        // toggle closes the former and reopens the latter; close() alone
        // would drop a press made during the 185 ms close.
        if (typeof surface.toggle === "function") surface.toggle();
        else surface.close();
    }

    /// Escape closes the topmost modal, or the active panel if there is none.
    /// Returns true when something actually handled it, so a caller can decide
    /// whether the key press is still unconsumed.
    function handleEscape() {
        var target = Stack.escapeTarget(modals, activePanel, isInactiveModal);
        if (target.type === "modal") {
            if (target.surface && typeof target.surface.close === "function") {
                target.surface.close();
                return true;
            }
            // A modal that cannot close itself must not swallow the key.
            return false;
        }
        if (target.type === "panel") return close(target.surface);
        return false;
    }

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
    //
    // There is deliberately no separate "visual" state: the controller records
    // intent and MorphSurface owns the animation, so a second copy of this
    // property could only ever lag behind this one and never be read.
    property string requestedState: stateIdle

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
            requestedState = stateIdle;
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
        // One panel at a time: every other panel is told to close before this
        // one is opened, so no two can ever be visible together.
        for (var key in panels) if (key !== name) closeSurface(key);
        // A panel opened over a full-screen modal would sit underneath it.
        closeModals(null);
        activePanel = name;
        requestedState = stateForPanel(name);
        if (typeof target.openPanel === "function") target.openPanel(name, originRect, initialSection || "");
        else if (typeof target.open === "function") target.open();
        isInteractive = true;
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
        requestedState = stateIdle;
        state = PanelController.State.Hidden;
        panelChanged("", requested);
        return true;
    }

    function closeAll() {
        closeModals(null);
        for (var key in panels) closeSurface(key);
        activePanel = "";
        previousPanel = "";
        isInteractive = false;
        requestedState = stateIdle;
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
        requestedState = stateIdle;
        state = PanelController.State.Hidden;
        panelChanged("", name);
    }
}