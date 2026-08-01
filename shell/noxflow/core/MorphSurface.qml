import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../config" as Config

// The only major-panel PanelWindow. Content views are ordinary Items loaded
// into this window, so geometry and input ownership never change during a
// panel switch.
//
// This is the EXECUTION layer of the shell state machine (design contract §6).
// It owns the morph phases:
//   opening:   preparing → expanding → crossfade → settled
//   closing:   disable-input → content-fade → frame-collapse (retain window
//              height) → surface-shrink → delayed unmount
//   swap:      crossfade one expanded view into another, retargeting geometry
//              in flight (never queues).
//
// The window geometry (topMargin/rightMargin/surfaceWidth/surfaceHeight) is the
// LAYER SURFACE bounds. The visual FRAME is the rounded Rectangle that morphs
// from the source chip to the target panel. On open the window expands
// immediately to avoid clipping; on close the window retains its size until
// the frame has collapsed.
PanelWindow {
    id: root
    required property var screen
    required property var panelComponents
    property string activePanel: ""
    property string pendingPanel: ""
    property rect originRect: Qt.rect(0, 0, 0, 0)
    property string initialSection: ""
    property bool active: activePanel !== "" || pendingPanel !== ""
    property real topMargin: targetTopMargin
    property real rightMargin: targetRightMargin
    property real surfaceWidth: targetWidth
    property real surfaceHeight: targetHeight
    readonly property real targetTopMargin: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingSm)
    readonly property real targetRightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    readonly property real targetBottomMargin: Theme.Tokens.scaled(Theme.Tokens.spacingLg)
    readonly property real targetWidth: activePanel === "calendar" ? Theme.Tokens.scaled(520) : Theme.Tokens.scaled(Config.ShellConfig.panelPreferredWidth)
    readonly property real targetHeight: activePanel === "media" ? Theme.Tokens.scaled(230) :
        (activePanel === "calendar" ? Theme.Tokens.scaled(650) :
        (activePanel === "notifications" ? Math.min(Theme.Tokens.scaled(760), screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700)) :
        Math.min(Theme.Tokens.scaled(720), screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700))))
    readonly property int morphDuration: Config.Motion.panelOpen
    property bool switching: pendingPanel !== ""

    // ── Morph phase (design contract §6) ──
    enum Phase { Settled, Preparing, Expanding, Crossfading, Collapsing }
    property int morphPhase: MorphSurface.Phase.Settled
    readonly property bool transitioning: morphPhase !== MorphSurface.Phase.Settled
    // Visual frame geometry (animates between chip and panel).
    property real frameTop: topMargin
    property real frameRight: rightMargin
    property real frameWidth: surfaceWidth
    property real frameHeight: surfaceHeight
    property real frameRadius: Theme.Tokens.radiusXl
    // Content choreography.
    property real compactOpacity: 1.0
    property real expandedOpacity: 0.0
    property real compactTranslate: 0.0
    property real expandedTranslate: 0.0
    // Origin chip visual (mirrored from the bar chip that opened the panel).
    property string compactIcon: ""
    property string compactLabel: ""
    property color compactAccent: Theme.Tokens.textPrimary
    // Retained window height while collapsing (layer surface stays big until
    // the visual frame has collapsed).
    property bool retainWindow: false
    // True while a close animation is in flight. Guards closePanel() against
    // double-close and rapid re-open races (stuck-panel bug): a new openPanel()
    // always cancels a pending close.
    property bool closing: false
    // Prevent the host from interpreting the initial hidden state of a newly
    // loaded child as a user-requested close.
    property bool contentReady: false

    screen: root.screen
    anchors.top: true; anchors.right: true
    margins.top: topMargin; margins.right: rightMargin
    implicitWidth: surfaceWidth; implicitHeight: surfaceHeight
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: root.active

    // Layer-surface geometry transitions (OutCubic, no overshoot).
    Behavior on topMargin { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on rightMargin { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on surfaceWidth { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
    Behavior on surfaceHeight { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }

    // ── Visual frame (the morphing surface) ──
    Rectangle {
        id: frame
        anchors.top: parent.top; anchors.right: parent.right
        width: root.frameWidth; height: root.frameHeight
        radius: root.frameRadius
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault; border.width: 1

        Behavior on width { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: Config.Motion.geometry; NumberAnimation { duration: root.morphDuration; easing.type: Easing.OutCubic } }
        Behavior on radius { enabled: Config.Motion.geometry; NumberAnimation { duration: Config.Motion.panelSwitch; easing.type: Easing.OutCubic } }

        // Compact content (origin chip) — mirrors the bar chip that opened the
        // panel. Fades out on open, back in on close while the frame collapses.
        Item {
            id: compactContent
            anchors.fill: parent
            opacity: root.compactOpacity
            visible: root.compactOpacity > 0.01
            transform: Translate { y: root.compactTranslate }
            Behavior on opacity { NumberAnimation { duration: Config.Motion.contentExit; easing.type: Easing.OutCubic } }
            Behavior on transform { PropertyAnimation { duration: Config.Motion.contentExit; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.centerIn: parent
                spacing: Theme.Tokens.spacingXs
                visible: root.compactIcon !== ""
                Text {
                    text: root.compactIcon
                    color: root.compactAccent
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: Theme.Tokens.scaled(Theme.Tokens.iconSm)
                }
                Text {
                    text: root.compactLabel
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyBodySmall
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }

        // Expanded content (the loaded panel) — fades in after geometry start.
        Loader {
            id: content
            anchors.fill: parent
            active: root.activePanel !== "" || root.pendingPanel !== ""
            sourceComponent: root.panelComponents && root.activePanel
                ? (root.panelComponents[root.activePanel] || null) : null
            opacity: root.expandedOpacity
            visible: root.expandedOpacity > 0.01
            transform: Translate { y: root.expandedTranslate }
            Behavior on opacity { NumberAnimation { duration: Config.Motion.contentEnter; easing.type: Easing.OutCubic } }
            Behavior on transform { PropertyAnimation { duration: Config.Motion.contentEnter; easing.type: Easing.OutCubic } }
            onLoaded: {
                root.contentReady = false;
                if (item && root.initialSection !== "" && item.initialSection !== undefined)
                    item.initialSection = root.initialSection;
                if (item && typeof item.open === "function") item.open();
                contentReadyTimer.restart();
            }
        }

        // Child surfaces own their lifecycle because they also expose Escape
        // and close buttons. Once such a child becomes hidden by itself, the
        // morph host must collapse too, otherwise an empty frame remains.
        Connections {
            target: content.item
            function onVisibleChanged() {
                if (root.contentReady && !root.closing && root.activePanel !== "" && content.item && !content.item.visible)
                    root.closePanel();
            }
        }
    }

    Timer {
        id: contentReadyTimer
        interval: Math.max(1, root.morphDuration + 24)
        repeat: false
        onTriggered: {
            if (root.activePanel !== "" && !root.closing)
                root.contentReady = true;
        }
    }

    // ── Phase timers ──
    // Geometry swap during a panel switch: retarget the frame to the new
    // panel's geometry immediately, swap content at the midpoint.
    Timer {
        id: swapTimer
        interval: Math.max(1, Math.round(Config.Motion.panelSwitch * 0.5))
        repeat: false
        onTriggered: {
            root.closing = false;
            root.activePanel = root.pendingPanel;
            root.pendingPanel = "";
            // The Loader fades in the new content itself (onLoaded → item.open
            // drives the SurfaceLifecycle animation). The crossfade keeps a
            // residual opacity so the new content inherits a smooth entrance.
            root.expandedOpacity = 1.0;
            root.expandedTranslate = 0.0;
            root.morphPhase = MorphSurface.Phase.Settled;
        }
    }

    // Close sequence: after the frame has collapsed, shrink the layer surface
    // and unmount content.
    Timer {
        id: collapseTimer
        interval: Math.max(1, Math.round(root.morphDuration * 0.9))
        repeat: false
        onTriggered: {
            root.closing = false;
            root.retainWindow = false;
            root.activePanel = "";
            root.pendingPanel = "";
            root.morphPhase = MorphSurface.Phase.Settled;
            root.compactOpacity = 1.0;
            root.compactTranslate = 0.0;
        }
    }

    function componentFor(name) { return root.panelComponents ? (root.panelComponents[name] || null) : null; }

    // Origin chip visuals for each panel (mirrors the bar chip).
    function panelOriginInfo(name) {
        switch (name) {
            case "calendar":       return { icon: "\uF133", label: "", accent: Theme.Tokens.textPrimary };
            case "media":          return { icon: "\uF001", label: "", accent: Theme.Tokens.tonalSecondary };
            case "notifications":  return { icon: "\uF0F3", label: "", accent: Theme.Tokens.stateInfo };
            case "quick-settings": return { icon: "\uF013", label: "", accent: Theme.Tokens.textPrimary };
            case "system-monitor": return { icon: "\uF080", label: "", accent: Theme.Tokens.textPrimary };
            case "wallpaper":      return { icon: "\uF03E", label: "", accent: Theme.Tokens.textPrimary };
            case "clipboard":      return { icon: "\uF0EA", label: "", accent: Theme.Tokens.textPrimary };
            case "quick-share":    return { icon: "\uF064", label: "", accent: Theme.Tokens.textPrimary };
            default:               return { icon: "\uF013", label: "", accent: Theme.Tokens.textPrimary };
        }
    }

    function applyOrigin(name) {
        var info = panelOriginInfo(name);
        compactIcon = info.icon;
        compactLabel = info.label;
        compactAccent = info.accent;
    }

    function geometryFor(name, rect) {
        var hasOrigin = rect && rect.width > 0 && rect.height > 0;
        if (hasOrigin) return { top: Math.max(0, rect.y), right: Math.max(0, screen.width - rect.x - rect.width), width: rect.width, height: rect.height };
        return targetGeometryFor(name);
    }

    // Destination geometry for the expanded panel. Keep this separate from
    // geometryFor(), whose origin override is intentionally the clicked bar
    // chip. Mixing the two leaves the loaded panel clipped to chip size.
    function targetGeometryFor(name) {
        var width = name === "calendar" ? Theme.Tokens.scaled(520) : Theme.Tokens.scaled(Config.ShellConfig.panelPreferredWidth);
        var height = name === "media" ? Theme.Tokens.scaled(230) :
            (name === "calendar" ? Theme.Tokens.scaled(650) :
            (name === "notifications" ? Math.min(Theme.Tokens.scaled(760), screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700)) :
            Math.min(Theme.Tokens.scaled(720), screen ? screen.height - targetTopMargin - targetBottomMargin : Theme.Tokens.scaled(700))));
        return { top: targetTopMargin, right: targetRightMargin, width: width, height: height };
    }

    // Open a panel with the full phased morph.
    function openPanel(name, rect, section) {
        if (!componentFor(name)) return false;
        // A new open always cancels a pending close (rapid toggle-close→open).
        root.closing = false;
        root.contentReady = false;
        collapseTimer.stop();
        swapTimer.stop();
        if (rect && rect.width > 0 && rect.height > 0) originRect = rect;
        initialSection = section || "";

        // Toggle behavior: opening the already-open panel closes it.
        if (activePanel === name && pendingPanel === "") { closePanel(); return true; }

        var hasOrigin = rect && rect.width > 0 && rect.height > 0;
        var target = targetGeometryFor(name);

        if (activePanel !== "" && activePanel !== name) {
            // Swap: retarget geometry + crossfade content.
            pendingPanel = name;
            root.morphPhase = MorphSurface.Phase.Crossfading;
            // Close the outgoing panel's own lifecycle before swapping content
            // (stops its timers, fires its closed() signal).
            if (content && content.item && typeof content.item.close === "function") {
                content.item.close();
            }
            // Immediately size the layer surface to the new target to avoid
            // clipping; the frame retargets to the new geometry.
            topMargin = targetTopMargin; rightMargin = targetRightMargin;
            surfaceWidth = target.width; surfaceHeight = target.height;
            frameTop = targetTopMargin; frameRight = targetRightMargin;
            frameWidth = target.width; frameHeight = target.height; frameRadius = Theme.Tokens.radiusXl;
            // Origin chip visual updates for the incoming panel.
            applyOrigin(name);
            // Crossfade: fade expanded content out quickly, then swap in the
            // new content via the Loader at the midpoint.
            expandedOpacity = 0.35;
            expandedTranslate = Theme.Tokens.scaled(6);
            swapTimer.restart();
            return true;
        }

        // Fresh open.
        root.morphPhase = MorphSurface.Phase.Preparing;
        activePanel = name;
        content.active = true;
        applyOrigin(name);

        if (hasOrigin) {
            // Phase 1: capture source geometry, size the window to the chip.
            var sourceG = geometryFor(name, rect);
            topMargin = sourceG.top; rightMargin = sourceG.right;
            surfaceWidth = sourceG.width; surfaceHeight = sourceG.height;
            frameTop = sourceG.top; frameRight = sourceG.right;
            frameWidth = sourceG.width; frameHeight = sourceG.height;
            frameRadius = Theme.Tokens.radiusPill;
            // Content starts hidden; compact content shows the origin.
            compactOpacity = 1.0; compactTranslate = 0.0;
            expandedOpacity = 0.0;
            root.morphPhase = MorphSurface.Phase.Expanding;
            // Phase 2: animate window + frame to target.
            Qt.callLater(function() {
                topMargin = targetTopMargin; rightMargin = targetRightMargin;
                surfaceWidth = target.width; surfaceHeight = target.height;
                frameTop = targetTopMargin; frameRight = targetRightMargin;
                frameWidth = target.width; frameHeight = target.height; frameRadius = Theme.Tokens.radiusXl;
                // Phase 3: crossfade at ~40% of the geometry transition.
                expandFadeTimer.restart();
            });
        } else {
            // No origin chip: just appear.
            topMargin = target.top; rightMargin = target.right; surfaceWidth = target.width; surfaceHeight = target.height;
            frameTop = target.top; frameRight = target.right; frameWidth = target.width; frameHeight = target.height; frameRadius = Theme.Tokens.radiusXl;
            compactOpacity = 0.0; compactTranslate = -Theme.Tokens.scaled(6);
            expandedOpacity = 1.0; expandedTranslate = 0.0;
            root.morphPhase = MorphSurface.Phase.Settled;
        }
        return true;
    }

    Timer {
        id: expandFadeTimer
        interval: Math.max(1, Math.round(root.morphDuration * 0.4))
        repeat: false
        onTriggered: {
            // Crossfade: fade compact content out, expanded content in.
            compactOpacity = 0.0;
            compactTranslate = -Theme.Tokens.scaled(6);
            expandedOpacity = 1.0;
            expandedTranslate = 0.0;
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: Math.max(1, Math.round(root.morphDuration * 0.6))
        repeat: false
        onTriggered: { root.morphPhase = MorphSurface.Phase.Settled; }
    }

    // Close with retained window height: disable interaction, fade content,
    // collapse the frame to the origin, then shrink the window.
    function closePanel() {
        if (root.closing || (!activePanel && !pendingPanel)) return false;
        root.closing = true;
        root.contentReady = false;
        contentReadyTimer.stop();
        swapTimer.stop();
        pendingPanel = "";
        root.morphPhase = MorphSurface.Phase.Collapsing;
        // Let the loaded panel run its own close lifecycle first (stops its
        // timers, fires its closed() signal), then fade the expanded content.
        if (content && content.item && typeof content.item.close === "function") {
            content.item.close();
        }
        // Disable interaction (content surfaces use lifecycle.active which is
        // driven by their own open()/close(); here we just fade).
        expandedOpacity = 0.0;
        expandedTranslate = Theme.Tokens.scaled(6);
        // Compact content comes back.
        compactOpacity = 1.0;
        compactTranslate = 0.0;

        // Collapse the visual frame toward the origin chip.
        var g = geometryFor(activePanel || "quick-settings", originRect);
        var hasOrigin = originRect && originRect.width > 0 && originRect.height > 0;
        if (hasOrigin) {
            frameTop = g.top; frameRight = g.right; frameWidth = g.width; frameHeight = g.height;
            frameRadius = Theme.Tokens.radiusPill;
            // Retain the layer window size until the frame finishes collapsing.
            root.retainWindow = true;
            collapseTimer.restart();
        } else {
            // No origin: fade out and unmount.
            topMargin = g.top; rightMargin = g.right; surfaceWidth = g.width; surfaceHeight = g.height;
            collapseTimer.interval = Math.max(1, Math.round(Config.Motion.contentExit));
            collapseTimer.restart();
        }
        return true;
    }

    function open() { if (activePanel) openPanel(activePanel, originRect); }
    function close() { closePanel(); }
}
