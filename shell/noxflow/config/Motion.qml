pragma Singleton
import QtQml
import "." as Config

QtObject {
    readonly property real factor: Config.ShellConfig.reduceMotion ? 0.15 : Config.ShellConfig.animationSpeed
    readonly property int micro: Math.max(1, Math.round(110 * factor))
    readonly property int hover: Math.max(1, Math.round(140 * factor))
    // Keep transitions expressive while staying inside a responsive frame
    // budget: geometry is the only expensive animation; content uses opacity
    // and translation so panels remain smooth on hybrid GPUs.
    readonly property int panelOpen: Math.max(1, Math.round(205 * factor))
    readonly property int panelSwitch: Math.max(1, Math.round(175 * factor))
    readonly property int panelClose: Math.max(1, Math.round(145 * factor))
    readonly property int contentEnter: Math.max(1, Math.round(125 * factor))
    readonly property int contentExit: Math.max(1, Math.round(95 * factor))
    readonly property int osdEnter: Math.max(1, Math.round(145 * factor))
    readonly property int osdExit: Math.max(1, Math.round(150 * factor))
    readonly property bool geometry: !Config.ShellConfig.reduceMotion
}
