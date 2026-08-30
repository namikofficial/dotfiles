pragma Singleton
import QtQml
import "." as Config

QtObject {
    readonly property real scale: Config.ShellConfig.uiScale
    readonly property real barHeight: Config.ShellConfig.barHeight * scale
    readonly property real barMargin: Config.ShellConfig.barMargin * scale
    readonly property real panelGap: 8 * scale
    readonly property real panelRadius: 24 * scale
    readonly property real cardRadius: 16 * scale
    readonly property real controlHeight: 40 * scale
    readonly property real compactPanelWidth: 380 * scale
    readonly property real calendarPanelWidth: 520 * scale
    function fitPanelWidth(screenWidth, preferred) { return Math.min(preferred || calendarPanelWidth, screenWidth - 2 * barMargin); }
    function fitPanelHeight(screenHeight) { return Math.min(720 * scale, screenHeight - barHeight - 2 * barMargin); }
}
