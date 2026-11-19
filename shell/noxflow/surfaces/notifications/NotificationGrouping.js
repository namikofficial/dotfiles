.pragma library

function groupByApp(items) {
    if (!Array.isArray(items) || items.length === 0) return [];
    var groups = [];
    var byKey = {};
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (!item) continue;
        var rawApp = item.app_name !== undefined && item.app_name !== null
            ? String(item.app_name).trim()
            : "";
        var appName = rawApp !== "" ? rawApp : "System";
        var key = appName.toLowerCase();
        var group = byKey[key];
        if (!group) {
            group = {
                key: key,
                appName: appName,
                count: 0,
                items: []
            };
            byKey[key] = group;
            groups.push(group);
        }
        group.items.push(item);
        group.count = group.items.length;
    }
    return groups;
}

function estimatePanelHeight(activeCount, privacyRedacted, scaledFn) {
    var scale = typeof scaledFn === "function"
        ? scaledFn
        : function(value) { return value; };
    var count = Math.max(0, Math.floor(Number(activeCount) || 0));
    if (privacyRedacted || count === 0) {
        return scale(310);
    }
    return scale(188 + count * 108);
}
