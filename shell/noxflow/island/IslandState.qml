import QtQml
import "../theme" as Theme
import "IslandRoutes.js" as Routes

// IslandState.qml — the island's derived state and guard values.
//
// Extracted from IslandHost.qml, which carried this alongside the view, the
// queue and the engagement machine. Nothing here is visual; it is the state
// those pieces read.
//
// The old file also listed a `states` array naming six kinds — recording,
// file-transfer, ai-completion, build-result, mic, network-warning — that no
// producer in the shell could ever produce. The set of live kinds now comes
// from IslandRoutes.js, and test_island_contract.sh asserts the two agree.



QtObject {
    id: root

    // ── Inputs ──
    property var screen: null
    required property var hyprland
    required property var audio
    required property var brightness
    property var activityController: null

    // ── Mirrored from the host ──
    // Only `islandState` is mirrored: the one derived value that depends on it
    // is `dashboardVisible`. The host used to push expanded/hoverExpanded/
    // currentKind/panelOpen/calendarExpanded/launcherVisible in here as well,
    // but nothing read them back, so the mirror was a one-way copy that made
    // `now` a write-only property and produced "Unable to assign [undefined]
    // to bool" for the absent properties at load.
    property string islandState: "idle"

    // ── Active window info ──
    // Derived from hyprland rather than cached, so a window-close event is
    // reflected on the next binding evaluation with no invalidation dance.
    readonly property string activeWin: {
        var window = root.hyprland ? root.hyprland.activeWindow : null;
        if (!window || typeof window !== "object") return "";
        return String(window.title || window.class || window.application_id || "").trim();
    }
    readonly property string activeApp: {
        var window = root.hyprland ? root.hyprland.activeWindow : null;
        if (!window) return "";
        var raw = String(window.application_id || window.class || window.appid
            || window.initialClass || "").trim();
        if (!raw) return "";
        var pieces = raw.split(".");
        var label = pieces[pieces.length - 1].replace(/[-_]+/g, " ").trim();
        return label ? label.charAt(0).toUpperCase() + label.slice(1) : raw;
    }

    // Whether the island shows a dashboard body rather than a compact pill.
    // Read from the route table so a kind cannot be a dashboard without a route.
    readonly property bool dashboardVisible: Routes.route(root.islandState).dashboard

    readonly property int displayPercent:
        Math.round(activityMaximum > 0 ? (activityValue / activityMaximum * 100) : activityValue)

    property real activityValue: 0
    property real activityMaximum: 100

    // ── Geometry ──
    readonly property real launcherHeight: root.screen
        ? Math.min(root.screen.height - Theme.Tokens.scaled(24),
                   Theme.Tokens.scaled(Theme.Tokens.islandLauncherHeight))
        : Theme.Tokens.scaled(Theme.Tokens.islandLauncherHeight)
    readonly property real calendarHeight: root.screen
        ? Math.min(root.screen.height - Theme.Tokens.scaled(24), Theme.Tokens.scaled(650))
        : Theme.Tokens.scaled(650)
    readonly property real expandW: root.screen
        ? Math.min(root.screen.width - Theme.Tokens.scaled(24),
                   Theme.Tokens.scaled(Theme.Tokens.islandDashboardMaxWidth))
        : Theme.Tokens.scaled(Theme.Tokens.islandDashboardMaxWidth)

}