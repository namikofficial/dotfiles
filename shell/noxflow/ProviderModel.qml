import QtQml

QtObject {
    property string providerName: ""
    property string status: "pending"
    readonly property bool available: status === "available"
    readonly property bool degraded: status === "degraded"
    // True once the first real daemon snapshot has been applied to this model.
    // Until then, numeric properties hold defaults and must not drive UI
    // transitions (e.g. the island OSD must not flash on login).
    property bool hasSynced: false
    property var data: ({})
}
