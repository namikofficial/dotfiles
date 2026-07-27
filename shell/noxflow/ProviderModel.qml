import QtQml

QtObject {
    property string providerName: ""
    property string status: "pending"
    readonly property bool available: status === "available"
    readonly property bool degraded: status === "degraded"
    property var data: ({})
}
