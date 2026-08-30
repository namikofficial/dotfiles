// InstanceTracker — generic per-screen instance registry.
// Replaces 6× copy-pasted push/splice tracking in shell.qml.
// Usage:
//   InstanceTracker { id: ccTracker }
//   ccTracker.add(screen, instance)
//   ccTracker.forScreen(screen) → instance or fallback

import QtQml
import Quickshell

QtObject {
    id: root

    property var instances: []  // [{ screen, instance }]
    property var focusedScreen: null

    function add(screen, instance) {
        // Remove existing for this screen
        remove(screen);
        instances.push({ screen: screen, instance: instance });
    }

    function remove(screen) {
        for (var i = instances.length - 1; i >= 0; i--) {
            if (instances[i].screen === screen) {
                instances.splice(i, 1);
                return;
            }
        }
    }

    function forScreen(screen) {
        for (var i = 0; i < instances.length; i++) {
            if (instances[i].screen === screen) return instances[i].instance;
        }
        // Fallback to focused screen or first
        if (focusedScreen) return focusedScreen;
        return instances.length > 0 ? instances[0].instance : null;
    }

    function toggle() {
        var inst = forScreen(Quickshell.activeScreen || null);
        if (inst && typeof inst.toggle === "function") inst.toggle();
    }

    function open() {
        var inst = forScreen(Quickshell.activeScreen || null);
        if (inst && typeof inst.open === "function") inst.open();
    }

    function close() {
        var inst = forScreen(Quickshell.activeScreen || null);
        if (inst && typeof inst.close === "function") inst.close();
    }
}
