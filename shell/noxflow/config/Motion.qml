pragma Singleton
import QtQml
import "." as Config

QtObject {
    readonly property real factor: Config.ShellConfig.reduceMotion ? 0.15 : Config.ShellConfig.animationSpeed
    readonly property int micro: Math.max(1, Math.round(110 * factor))
    readonly property int hover: Math.max(1, Math.round(140 * factor))
    readonly property int panelOpen: Math.max(1, Math.round(240 * factor))
    readonly property int panelSwitch: Math.max(1, Math.round(205 * factor))
    readonly property int panelClose: Math.max(1, Math.round(165 * factor))
    readonly property int contentEnter: Math.max(1, Math.round(150 * factor))
    readonly property int contentExit: Math.max(1, Math.round(115 * factor))
    readonly property int osdEnter: Math.max(1, Math.round(145 * factor))
    readonly property int osdExit: Math.max(1, Math.round(150 * factor))
    readonly property bool geometry: !Config.ShellConfig.reduceMotion
}
