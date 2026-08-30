pragma Singleton
import QtQml

// User-facing shell settings. Keep behaviour in one place so monitor scale and
// reduced-motion changes do not require editing individual surfaces.
QtObject {
    id: root
    readonly property int barHeight: 38
    readonly property int barMargin: 8
    readonly property real uiScale: 1.0
    readonly property real animationSpeed: 1.0
    readonly property bool reduceMotion: false
    readonly property bool enableBlur: false
    readonly property bool showWindowTitle: true
    readonly property bool showMediaInBar: true
    readonly property string clockFormat: "HH:mm"
    readonly property string dateFormat: "ddd, d MMM"
    readonly property string temperatureUnit: "C"
    readonly property int batteryWarningThreshold: 20
    readonly property int batteryCriticalThreshold: 8
    readonly property int notificationHistoryLimit: 50
    readonly property int panelPreferredWidth: 420
    readonly property int calendarWeekStart: 1
}
