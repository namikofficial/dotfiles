// MorphRegistry — the single source of truth for bar → panel ownership.
// Every panel trigger is registered with screen coordinates and enough
// metadata for the host surface to reproduce the interaction exactly.

import QtQml

QtObject {
    id: root

    property var triggers: ({})

    function registerChip(id, chipRect) {
        registerTrigger(id, "", chipRect, 999);
    }

    function unregisterChip(id) {
        unregisterTrigger(id, "");
    }

    function chipRect(id) {
        var record = trigger(id, "");
        return record ? Qt.rect(record.globalX, record.globalY, record.globalWidth, record.globalHeight) : Qt.rect(0, 0, 0, 0);
    }

    function registerTrigger(panelId, monitorName, geometry, cornerRadius, triggerId) {
        if (!geometry || geometry.width <= 0 || geometry.height <= 0 || !panelId) return false;
        var next = {};
        for (var key in triggers) next[key] = triggers[key];
        next[(monitorName || "*") + ":" + (triggerId || panelId)] = {
            panelId: panelId,
            monitorName: monitorName || "",
            globalX: Number(geometry.x),
            globalY: Number(geometry.y),
            globalWidth: Number(geometry.width),
            globalHeight: Number(geometry.height),
            cornerRadius: Number(cornerRadius || 999)
        };
        triggers = next;
        return true;
    }

    function unregisterTrigger(panelId, monitorName) {
        var removeKey = (monitorName || "*") + ":" + panelId;
        if (!triggers[removeKey]) return;
        var next = {};
        for (var key in triggers) if (key !== removeKey) next[key] = triggers[key];
        triggers = next;
    }

    function trigger(panelId, monitorName, triggerId) {
        var id = triggerId || panelId;
        return triggers[(monitorName || "*") + ":" + id] || triggers["*:" + id] || null;
    }
}
