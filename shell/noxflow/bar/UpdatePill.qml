import QtQuick
import "../theme" as Theme
import "." as Local

// UpdatePill.qml — package-update state in the bar's right zone.
//
// This is the single update control. The bar previously carried a second,
// permanently hidden copy in its left zone; two controls meant two sources of
// truth about what the update pill was doing.



Local.BarStatusPill {
    id: root

    // launchState: "idle" | "opening" | "opened" | "failed"
    required property string launchState
    required property bool checked
    required property int count
    required property string launchMessage
    required property string detailTooltip

    signal runUpdate()
    signal refreshRequested()
    signal hoverChangedToIsland(bool hovered)

    // The update pill has a fixed minimum width so the bar does not reflow
    // when a check completes and the count goes 3 -> 0.
    minimumWidth: Theme.Tokens.scaled(58)
    horizontalPadding: Theme.Tokens.scaled(9)
    occupied: true
    failed: launchState === "failed"

    onTapped: root.runUpdate()
    onSecondaryTapped: root.refreshRequested()

    property bool hover: false
    onHoverChanged: function(hovered) { root.hover = hovered; root.hoverChangedToIsland(hovered) }

    readonly property string label: {
        if (launchState === "failed") return "UP !";
        if (launchState === "opening") return "UP …";
        if (!checked) return "UP …";
        return "UP " + String(count);
    }
    readonly property string icon: {
        if (launchState === "failed") return "";
        if (!checked) return "";
        if (count > 0) return "";
        return "";
    }
    readonly property color labelColor: {
        if (launchState === "failed") return Theme.Tokens.stateDanger;
        if (count > 0) return Theme.Tokens.textPrimary;
        return Theme.Tokens.textMuted;
    }
    readonly property color iconColor: {
        if (launchState === "failed") return Theme.Tokens.stateDanger;
        if (!checked) return Theme.Tokens.textMuted;
        if (count > 0) return Theme.Tokens.stateInfo;
        return Theme.Tokens.textMuted;
    }

    tooltipText: launchMessage !== ""
        ? launchMessage
        : !checked
            ? "Checking for updates…"
            : detailTooltip !== ""
                ? detailTooltip + " · click to update, right-click to refresh"
                : "Click to update · right-click to refresh"

    Text {
        text: root.icon
        color: root.iconColor
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
    Text {
        text: root.label
        color: root.labelColor
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyLabelSmall
        font.bold: root.count > 0 || root.launchState === "failed"
    }
}