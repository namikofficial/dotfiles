pragma Singleton
import QtQml
import "." as Config
import "../theme" as Theme

// Named durations for panels, content and OSDs. The numbers live in
// theme/Tokens.qml (the motion table); this file only names them and applies
// the user's animation speed. Reduced motion comes from Tokens.duration(),
// the same rule every other animation uses. Never 0: some of these drive
// Timer intervals.
QtObject {
    readonly property real speed: Config.ShellConfig.animationSpeed
    function scaled(value) { return Math.max(1, Math.round(Theme.Tokens.duration(value) * speed)); }

    readonly property int micro: scaled(Theme.Tokens.motionMicro)
    readonly property int hover: scaled(Theme.Tokens.motionHover)
    // Geometry is the only expensive animation; content uses opacity and
    // translation so panels stay smooth on hybrid GPUs.
    readonly property int panelOpen: scaled(Theme.Tokens.motionPanelOpen)
    readonly property int panelSwitch: scaled(Theme.Tokens.motionPanelSwitch)
    readonly property int panelClose: scaled(Theme.Tokens.motionPanelClose)
    readonly property int contentEnter: scaled(Theme.Tokens.motionContentEnter)
    readonly property int contentExit: scaled(Theme.Tokens.motionContentExit)
    readonly property int osdEnter: scaled(Theme.Tokens.motionOsdEnter)
    readonly property int osdExit: scaled(Theme.Tokens.motionOsdExit)
    readonly property bool geometry: !Theme.Tokens.reducedMotion
}
