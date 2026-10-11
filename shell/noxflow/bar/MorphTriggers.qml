import QtQml
import QtQuick

// MorphTriggers.qml — keeps the panel-morph registry in step with the bar.
//
// The bar animates a panel out of the capsule the user pressed, so the
// registry has to know each capsule's global rectangle. That used to be a
// 250 ms timer that re-measured every pill four times a second for the life
// of the shell, whether or not anything had moved.
//
// Registration now runs on change: the bar's own width, the capsules whose
// content width varies (volume, updates, media), and the workspace list. A
// 100 ms coalescing timer absorbs bursts so one window drag does not trigger a
// dozen registrations.



QtObject {
    id: root

    // monitorName -> { panel, geometry } entries. The bar fills this in; this
    // object owns only the scheduling.
    property var registry: null
    property var bindings: null

    readonly property int coalesceMs: 100
    readonly property bool active: registry !== null && bindings !== null

    property Timer coalesce: Timer {
        interval: root.coalesceMs
        repeat: false
        onTriggered: root.registerAll()
    }

    function requestRegistration() {
        if (!root.active) return;
        coalesce.restart();
    }

    function registerAll() {
        if (!root.active) return;
        var entries = root.bindings();
        if (!entries) return;
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            root.registry.registerTrigger(
                entry.panel, entry.monitor,
                entry.geometry, entry.cornerRadius,
                entry.triggerId);
        }
    }
}