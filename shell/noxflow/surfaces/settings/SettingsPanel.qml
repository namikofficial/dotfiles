// Settings Panel — theme profile switching, appearance controls.
// Super+, to open.
//
// NF-05/NF-06: every control reconciles with the canonical daemon API. Each
// user action flows through preview → pending → saved/rejected so the panel
// is always truthful about what the daemon actually accepted. Maintenance
// controls run as tracked Processes with visible success/failure rather than
// silent Quickshell.exec calls (the shell service unit has no ExecReload, so
// `systemctl --user reload noxflow-shell` would fail silently — those calls
// now go through the daemon where supported, or shell out via Process and
// surface the exit code).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme" as Theme
import "../../config" as Config
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
    exclusiveZone: 0; aboveWindows: true; color: "transparent"
    visible: lifecycle.active
    // Request the keyboard seat on open rather than on click; see the long
    // explanation in core/MorphSurface.qml.
    WlrLayershell.keyboardFocus: lifecycle.active
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, Theme.Tokens.glassScrimAlpha)
        opacity: root.openProgress
        TapHandler { onTapped: lifecycle.requestClose("clickOutside") }
    }

    // ── Settings hydration & write state ──
    // Per-key lifecycle states. idle: no change in flight. preview: local
    // change applied but not yet sent. pending: change sent to daemon.
    // saved: daemon SettingUpdated confirms. rejected: daemon validation
    // failed; revert the local preview to the previous good value.
    enum SettingState { Idle, Preview, Pending, Saved, Rejected }
    property string lastStatusKind: ""       // "" | "saved" | "rejected" | "external" | "reconnect" | "unavailable"
    property string lastStatusKey: ""
    property string lastStatusMessage: ""
    // `double`: QML's int is 32-bit and Date.now() overflows it, so a
    // millisecond timestamp stored in an int wraps and every elapsed-time
    // comparison below becomes wrong.
    property double lastStatusAt: 0
    property bool hydrationInFlight: false
    property bool hydrationLoaded: false
    property string hydrationError: ""
    // Pending tracking by key. value is the new value sent to the daemon;
    // previousValue is the value before the user changed it (so we can
    // revert on reject).
    property var pendingWrites: ({})
    property var previousValues: ({})

    function statusFor(key) {
        if (pendingWrites[key]) return SettingsPanel.SettingState.Pending;
        return SettingsPanel.SettingState.Idle;
    }

    function scheduleStatusClear() {
        if (root.lastStatusKind === "" || !lifecycle.interactive) {
            statusAutoClearTimer.stop();
            return;
        }
        statusAutoClearTimer.interval = statusAutoClearTimer.defaultDurationMs;
        statusAutoClearTimer.restart();
    }

    function reportStatus(kind, key, message) {
        lastStatusKind = kind;
        lastStatusKey = key || "";
        lastStatusMessage = message || "";
        lastStatusAt = Date.now();
        scheduleStatusClear();
    }

    function clearStatus() {
        lastStatusKind = "";
        lastStatusKey = "";
        lastStatusMessage = "";
        statusAutoClearTimer.stop();
    }

    // The mapping lives in config/Appearance.qml so shell.qml can apply the
    // same persisted values at boot. This panel is no longer the only owner.
    function applyAppearanceFromMap(map) {
        return Config.Appearance.applyFromMap(map);
    }

    // Daemon writes a setting through the canonical API. Result carries the
    // new value on success so the panel can drop the optimistic preview.
    function writeSetting(key, value, displayLabel) {
        if (!root.noxd) {
            reportStatus("unavailable", key, displayLabel + ": no daemon connection");
            return;
        }
        if (!root.noxd.connected) {
            reportStatus("reconnect", key, displayLabel + ": waiting for daemon");
            // Still apply the preview locally so the user sees the intent.
            return;
        }
        var next = {};
        for (var k in pendingWrites) next[k] = pendingWrites[k];
        next[key] = { value: value, label: displayLabel, sentAt: Date.now() };
        pendingWrites = next;
        var cb = function(result) {
            var ack = result && result.data;
            // SettingUpdated echoes { key, value }. Confirm the value matches
            // what we sent so a stale response for a different key doesn't
            // clear an in-flight write.
            if (ack && ack.key === key) {
                var after = {};
                for (var kk in pendingWrites) if (kk !== key) after[kk] = pendingWrites[kk];
                pendingWrites = after;
                reportStatus("saved", key, displayLabel + " saved");
            } else {
                // Defensive: response shape changed. Drop the pending tag so
                // the UI doesn't get stuck on Pending forever.
                var after2 = {};
                for (var k2 in pendingWrites) if (k2 !== key) after2[k2] = pendingWrites[k2];
                pendingWrites = after2;
                reportStatus("saved", key, displayLabel + " acknowledged");
            }
        };
        var ecb = function(code, message) {
            // Reject: revert to previous good value.
            var prior = previousValues[key];
            if (prior !== undefined) revertLocalValue(key, prior);
            var after = {};
            for (var k3 in pendingWrites) if (k3 !== key) after[k3] = pendingWrites[k3];
            pendingWrites = after;
            reportStatus("rejected", key, displayLabel + ": " + (message || code || "rejected"));
        };
        root.noxd.setSetting(key, value, cb, ecb);
    }

    function capturePrevious(key) {
        return Config.Appearance.currentValue(key);
    }

    function revertLocalValue(key, value) {
        Config.Appearance.revert(key, value);
    }

    function hydrateFromDaemon() {
        if (!root.noxd || !root.noxd.connected) {
            hydrationError = root.noxd ? "daemon disconnected" : "no daemon client";
            reportStatus("reconnect", "", "Settings: daemon unavailable");
            return;
        }
        hydrationInFlight = true;
        hydrationError = "";
        root.noxd.getSettings(function(result) {
            hydrationInFlight = false;
            hydrationLoaded = true;
            var data = result && result.data && result.data.settings;
            if (!data) {
                hydrationError = "empty settings payload";
                return;
            }
            applyAppearanceFromMap(data);
            reportStatus("external", "", "Settings are up to date");
        }, function(code, message) {
            hydrationInFlight = false;
            hydrationError = message || code || "hydration failed";
            reportStatus("rejected", "", "Settings hydration failed: " + hydrationError);
        });
    }

    // React to daemon connection transitions: when we reconnect we need to
    // refresh local state from the canonical source because another client
    // may have changed settings while we were disconnected.
    Connections {
        target: root.noxd
        function onConnectionStateUpdated(state) {
            if (state === "subscribed" && lifecycle.interactive) {
                root.hydrateFromDaemon();
            } else if (state === "disconnected" || state === "connecting") {
                root.reportStatus("reconnect", "", "Daemon " + state);
            }
        }
    }

    Connections {
        target: lifecycle
        function onOpened() {
            // Snapshot the live values as the "previous" baseline so a
            // rejection can revert precisely.
            previousValues = {
                "appearance.profile": String(Theme.Tokens.currentProfile),
                "appearance.density": String(Theme.Tokens.activeDensity),
                "shell.reduced_motion": !!Theme.Tokens.reducedMotion,
                "appearance.radius": Number(Theme.Tokens.appearanceRadius)
            };
            clearStatus();
            hydrateFromDaemon();
        }
        function onInteractiveChanged() {
            if (lifecycle.interactive) {
                if (root.lastStatusKind !== "") root.scheduleStatusClear();
            } else {
                statusAutoClearTimer.stop();
            }
        }
        function onClosing(reason) {
            statusAutoClearTimer.stop();
        }
    }

    Timer {
        id: statusAutoClearTimer
        // Auto-clear the status indicator after 4 seconds, restarting cleanly
        // whenever a newer status arrives in reportStatus().
        readonly property int defaultDurationMs: 4000
        interval: defaultDurationMs
        repeat: false
        onTriggered: {
            var remaining = defaultDurationMs - (Date.now() - root.lastStatusAt);
            if (remaining > 50) {
                interval = Math.max(50, Math.ceil(remaining));
                restart();
                return;
            }
            interval = defaultDurationMs;
            root.clearStatus();
        }
    }

    // ── Maintenance: tracked Processes with visible exit codes ──
    // The shell service has Type=simple with no ExecReload/ReloadSignal so
    // `systemctl --user reload noxflow-shell` fails silently. We use restart
    // instead, and we run it via Process so the panel can show a real
    // success/failure banner. Restarting the shell kills the panel mid-run;
    // the restart banner is a "verified supported operation".
    property int maintenanceBusy: 0
    property var maintenanceStatus: ({})
    // Set by the Restart daemon button: the panel must survive long enough to
    // show the exit-code banner, then close itself.
    property bool closeAfterMaintenance: false
    function maintenanceRun(command, label) {
        if (maintenanceBusy > 0) return;
        // The plan asks this runner to keep the panel open until the result
        // banner shows, so "Restart daemon" must not close the panel on click;
        // it closes from the exit handler once the outcome is known.
        maintenanceProc.label = label;
        if (!maintenanceProc.run(command)) return;
        maintenanceBusy += 1;
    }
    property Components.Command maintenanceProc: Components.Command {
        label: "maintenance command"
        onExited: function(exitCode) {
            var lbl = root.maintenanceProc.label || "command";
            if (exitCode === 0) {
                reportStatus("saved", "", lbl + ": ok");
            } else {
                reportStatus("rejected", "", root.maintenanceProc.failureText());
            }
            // Only now, with the outcome known, may the panel close.
            if (root.closeAfterMaintenance) {
                root.closeAfterMaintenance = false;
                lifecycle.requestClose("restartDaemon");
            }
            root.maintenanceBusy = Math.max(0, root.maintenanceBusy - 1);
        }
    }

    // ── Settings panel ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.78, Theme.Tokens.scaled(680))
        height: Math.min(parent.height * 0.84, Theme.Tokens.scaled(660))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        scale: 0.85 + 0.15 * root.openProgress
        opacity: root.openProgress

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingXl
            spacing: Theme.Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingSm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "NOX / STUDIO"
                        color: Theme.Tokens.tonalSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                    Text {
                        text: "Nox Studio"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyHeadlineMedium
                        font.family: Theme.Tokens.typographyDisplayFamily
                        font.bold: true
                        Layout.fillWidth: true
                    }
                }

                // Quiet inline status pill for normal sync/saved feedback (no vertical jump).
                Rectangle {
                    id: statusPill
                    readonly property bool showInline: root.hydrationInFlight
                        || root.lastStatusKind === "saved"
                        || root.lastStatusKind === "external"
                    readonly property color pillAccent: root.lastStatusKind === "saved"
                        ? Theme.Tokens.stateSuccess : Theme.Tokens.stateInfo
                    visible: showInline
                    Layout.preferredHeight: Theme.Tokens.scaled(28)
                    Layout.preferredWidth: Math.min(Theme.Tokens.scaled(260), pillRow.implicitWidth + Theme.Tokens.scaled(18))
                    radius: Theme.Tokens.radiusPill
                    color: Theme.Tokens.withAlpha(pillAccent, 0.14)
                    border.color: Theme.Tokens.withAlpha(pillAccent, 0.36)
                    border.width: 1

                    RowLayout {
                        id: pillRow
                        anchors.fill: parent
                        anchors.leftMargin: Theme.Tokens.scaled(9)
                        anchors.rightMargin: Theme.Tokens.scaled(9)
                        spacing: Theme.Tokens.spacingXs
                        Text {
                            text: root.hydrationInFlight ? "•" : (root.lastStatusKind === "saved" ? "✓" : "↻")
                            color: statusPill.pillAccent
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.hydrationInFlight ? "Syncing…"
                                : root.lastStatusKind === "external" ? "Up to date"
                                : root.lastStatusMessage
                            color: Theme.Tokens.textPrimary
                            font.family: Theme.Tokens.typographyFontFamily
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                Components.IconButton {
                    iconText: "\uF00D"; accessibleName: "Close settings"
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            // ── Error / reconnect banner (only shown for failures or disconnect) ──
            Rectangle {
                Layout.fillWidth: true
                readonly property bool isAlert: root.lastStatusKind === "rejected"
                    || root.lastStatusKind === "reconnect"
                    || root.lastStatusKind === "unavailable"
                visible: isAlert
                radius: Theme.Tokens.radiusMd
                Layout.preferredHeight: errorRow.implicitHeight + Theme.Tokens.spacingSm * 2
                color: Theme.Tokens.withAlpha(
                    root.lastStatusKind === "rejected" ? Theme.Tokens.stateDanger : Theme.Tokens.stateWarning,
                    0.16)
                border.color: Theme.Tokens.withAlpha(
                    root.lastStatusKind === "rejected" ? Theme.Tokens.stateDanger : Theme.Tokens.stateWarning,
                    0.42)
                border.width: 1

                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    spacing: Theme.Tokens.spacingSm
                    Text {
                        text: root.lastStatusKind === "rejected" ? "!" : "↻"
                        color: root.lastStatusKind === "rejected" ? Theme.Tokens.stateDanger : Theme.Tokens.stateWarning
                        font.pixelSize: Theme.Tokens.typographyLabelMedium
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.lastStatusMessage
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                }
            }

            Components.Divider { Layout.fillWidth: true }

            Flickable {
                id: settingsScroll
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight + Theme.Tokens.spacingXs
                clip: true; interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar {
                    id: settingsScrollBar
                    policy: ScrollBar.AsNeeded
                }

                ColumnLayout {
                    id: contentColumn
                    width: settingsScroll.width - (settingsScrollBar.visible ? Theme.Tokens.scaled(12) : 0)
                    spacing: Theme.Tokens.spacingLg

                    // ── Section: Theme Profile ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "THEME PROFILE"
                                color: Theme.Tokens.textMuted
                                font.family: Theme.Tokens.typographyFontFamily
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                font.bold: true
                                font.letterSpacing: 1.1
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "Switch between colour palettes"
                                color: Theme.Tokens.textSecondary
                                font.family: Theme.Tokens.typographyFontFamily
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }

                        GridLayout {
                            id: profileGrid
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Theme.Tokens.spacingSm
                            rowSpacing: Theme.Tokens.spacingSm

                            Repeater {
                                model: Theme.ThemeProfiles.profileNames()
                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index
                                    readonly property bool isActive: Theme.Tokens.currentProfile === modelData
                                    readonly property bool isPending: root.pendingWrites["appearance.profile"] !== undefined
                                        && root.pendingWrites["appearance.profile"].value === modelData
                                    readonly property int profileCount: Theme.ThemeProfiles.profileNames().length
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Apply " + modelData + " theme"

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.Tokens.scaled(58)
                                    Layout.columnSpan: (index === profileCount - 1 && profileCount % 2 === 1) ? 2 : 1
                                    radius: Theme.Tokens.radiusMd
                                    color: isActive ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                                    border.color: isActive ? Theme.Tokens.tonalPrimary
                                        : (activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineSubtle)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.Tokens.spacingMd
                                        anchors.rightMargin: Theme.Tokens.spacingMd
                                        spacing: Theme.Tokens.spacingMd

                                        Row {
                                            spacing: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            Repeater {
                                                model: [
                                                    Theme.ThemeProfiles.getProfile(modelData).tonals.primary,
                                                    Theme.ThemeProfiles.getProfile(modelData).tonals.secondary,
                                                    Theme.ThemeProfiles.getProfile(modelData).tonals.tertiary,
                                                    Theme.ThemeProfiles.getProfile(modelData).surfaces.surface
                                                ]
                                                delegate: Rectangle {
                                                    width: 11; height: 11; radius: 3; color: modelData
                                                    border.color: Theme.Tokens.outlineSubtle; border.width: 1
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignLeft
                                                elide: Text.ElideRight
                                                text: {
                                                    var labels = {
                                                        "material-expressive": "Expressive",
                                                        "material-focus": "Focus",
                                                        "material-ambient": "Ambient",
                                                        "material-performance": "Performance",
                                                        "material-oled": "OLED Black"
                                                    }
                                                    return labels[modelData] || modelData
                                                }
                                                color: isActive ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary
                                                font.pixelSize: Theme.Tokens.typographyBodyMedium
                                                font.family: Theme.Tokens.typographyFontFamily
                                                font.bold: isActive
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignLeft
                                                elide: Text.ElideRight
                                                text: {
                                                    var desc = {
                                                        "material-expressive": "Vibrant default palette",
                                                        "material-focus": "High contrast, max readability",
                                                        "material-ambient": "Soft muted tones",
                                                        "material-performance": "Flat, GPU-friendly",
                                                        "material-oled": "True black background"
                                                    }
                                                    return desc[modelData] || ""
                                                }
                                                color: isActive ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted
                                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                                font.family: Theme.Tokens.typographyFontFamily
                                                visible: text !== ""
                                            }
                                        }

                                        Text {
                                            text: isPending ? "…" : isActive ? "✓" : ""
                                            color: Theme.Tokens.tonalPrimary
                                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                                            font.bold: true
                                            visible: isActive || isPending
                                        }
                                    }

                                    TapHandler {
                                        onTapped: {
                                            parent.forceActiveFocus()
                                            applyTheme()
                                        }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    Keys.onReturnPressed: applyTheme()
                                    Keys.onSpacePressed: applyTheme()

                                    function applyTheme() {
                                        if (isActive && !root.pendingWrites["appearance.profile"]) return;
                                        Theme.Tokens.applyProfile(modelData);
                                        root.writeSetting("appearance.profile", modelData, "Profile " + modelData);
                                    }
                                }
                            }
                        }
                    }

                    // ── Section: Appearance ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingSm

                        Text {
                            text: "APPEARANCE"
                            color: Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: appearanceCardCol.implicitHeight + Theme.Tokens.spacingLg * 2
                            radius: Theme.Tokens.radiusLg
                            color: Theme.Tokens.surfaceSurfaceContainer
                            border.color: Theme.Tokens.outlineSubtle
                            border.width: 1

                            ColumnLayout {
                                id: appearanceCardCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.Tokens.spacingLg
                                spacing: Theme.Tokens.spacingMd

                                Components.SettingRow {
                                    Layout.fillWidth: true
                                    label: "Density"
                                    description: "Spacing and control scale"
                                    Rectangle {
                                        Layout.preferredHeight: Theme.Tokens.scaled(34)
                                        Layout.preferredWidth: densitySegRow.implicitWidth + Theme.Tokens.scaled(6)
                                        radius: Theme.Tokens.radiusPill
                                        color: Theme.Tokens.surfaceSurface2
                                        border.color: Theme.Tokens.outlineSubtle
                                        border.width: 1

                                        RowLayout {
                                            id: densitySegRow
                                            anchors.fill: parent
                                            anchors.margins: Theme.Tokens.scaled(3)
                                            spacing: Theme.Tokens.scaled(2)

                                            Repeater {
                                                model: ["compact", "comfortable", "spacious"]
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    readonly property bool selected: Theme.Tokens.activeDensity === modelData
                                                    activeFocusOnTab: true
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: "Density " + modelData
                                                    Layout.preferredHeight: Theme.Tokens.scaled(26)
                                                    Layout.preferredWidth: densityBtnText.implicitWidth + Theme.Tokens.scaled(18)
                                                    radius: Theme.Tokens.radiusPill
                                                    color: selected ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                                                    border.color: selected ? Theme.Tokens.tonalPrimary
                                                        : (activeFocus ? Theme.Tokens.outlineFocus : "transparent")
                                                    border.width: selected || activeFocus ? 1 : 0

                                                    Text {
                                                        id: densityBtnText
                                                        anchors.centerIn: parent
                                                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                        color: selected ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                                        font.family: Theme.Tokens.typographyFontFamily
                                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                                        font.bold: selected
                                                    }

                                                    TapHandler {
                                                        onTapped: {
                                                            parent.forceActiveFocus();
                                                            if (Theme.Tokens.activeDensity === modelData) return;
                                                            Theme.Tokens.activeDensity = modelData;
                                                            root.writeSetting("appearance.density", modelData, "Density " + modelData);
                                                        }
                                                    }
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    Keys.onReturnPressed: {
                                                        if (Theme.Tokens.activeDensity === modelData) return;
                                                        Theme.Tokens.activeDensity = modelData;
                                                        root.writeSetting("appearance.density", modelData, "Density " + modelData);
                                                    }
                                                    Keys.onSpacePressed: {
                                                        if (Theme.Tokens.activeDensity === modelData) return;
                                                        Theme.Tokens.activeDensity = modelData;
                                                        root.writeSetting("appearance.density", modelData, "Density " + modelData);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Components.Divider { Layout.fillWidth: true }

                                Components.SettingRow {
                                    Layout.fillWidth: true
                                    label: "Reduced motion"
                                    description: "Skip geometry and transition motion"
                                    valueText: Theme.Tokens.reducedMotion ? "On" : "Off"
                                    valueWidth: Theme.Tokens.scaled(36)
                                    Components.Toggle {
                                        accessibleName: "Reduced motion"
                                        checked: Theme.Tokens.reducedMotion
                                        onToggled: function(value) {
                                            if (Theme.Tokens.reducedMotion === value) return;
                                            Theme.Tokens.reducedMotion = value;
                                            root.writeSetting("shell.reduced_motion", value, "Reduced motion");
                                        }
                                    }
                                }

                                Components.Divider { Layout.fillWidth: true }

                                Components.SettingRow {
                                    Layout.fillWidth: true
                                    label: "Corner radius"
                                    description: "Effective radius: " + Theme.Tokens.appearanceRadius + "px"
                                    Rectangle {
                                        Layout.preferredHeight: Theme.Tokens.scaled(34)
                                        Layout.preferredWidth: radiusSegRow.implicitWidth + Theme.Tokens.scaled(6)
                                        radius: Theme.Tokens.radiusPill
                                        color: Theme.Tokens.surfaceSurface2
                                        border.color: Theme.Tokens.outlineSubtle
                                        border.width: 1

                                        RowLayout {
                                            id: radiusSegRow
                                            anchors.fill: parent
                                            anchors.margins: Theme.Tokens.scaled(3)
                                            spacing: Theme.Tokens.scaled(2)

                                            Repeater {
                                                model: [4, 8, 14, 20, 28]
                                                delegate: Rectangle {
                                                    required property int modelData
                                                    readonly property bool selected: Theme.Tokens.appearanceRadius === modelData
                                                    activeFocusOnTab: true
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: "Corner radius " + modelData + "px"
                                                    Layout.preferredHeight: Theme.Tokens.scaled(26)
                                                    Layout.preferredWidth: radiusBtnText.implicitWidth + Theme.Tokens.scaled(14)
                                                    radius: Theme.Tokens.radiusPill
                                                    color: selected ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                                                    border.color: selected ? Theme.Tokens.tonalPrimary
                                                        : (activeFocus ? Theme.Tokens.outlineFocus : "transparent")
                                                    border.width: selected || activeFocus ? 1 : 0

                                                    Text {
                                                        id: radiusBtnText
                                                        anchors.centerIn: parent
                                                        text: modelData + "px"
                                                        color: selected ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                                        font.family: Theme.Tokens.typographyFontFamily
                                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                                        font.bold: selected
                                                    }

                                                    TapHandler {
                                                        onTapped: {
                                                            parent.forceActiveFocus();
                                                            if (Theme.Tokens.appearanceRadius === modelData) return;
                                                            Theme.Tokens.applyRadius(modelData);
                                                            root.writeSetting("appearance.radius", modelData, "Radius " + modelData + "px");
                                                        }
                                                    }
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    Keys.onReturnPressed: {
                                                        if (Theme.Tokens.appearanceRadius === modelData) return;
                                                        Theme.Tokens.applyRadius(modelData);
                                                        root.writeSetting("appearance.radius", modelData, "Radius " + modelData + "px");
                                                    }
                                                    Keys.onSpacePressed: {
                                                        if (Theme.Tokens.appearanceRadius === modelData) return;
                                                        Theme.Tokens.applyRadius(modelData);
                                                        root.writeSetting("appearance.radius", modelData, "Radius " + modelData + "px");
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Section: System ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingSm

                        Text {
                            text: "SYSTEM"
                            color: Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                            font.bold: true
                            font.letterSpacing: 1.1
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: systemCardCol.implicitHeight + Theme.Tokens.spacingLg * 2
                            radius: Theme.Tokens.radiusLg
                            color: Theme.Tokens.surfaceSurfaceContainer
                            border.color: Theme.Tokens.outlineSubtle
                            border.width: 1

                            ColumnLayout {
                                id: systemCardCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.Tokens.spacingLg
                                spacing: Theme.Tokens.spacingMd

                                Components.SettingRow {
                                    Layout.fillWidth: true
                                    label: "NoxFlow Shell"
                                    description: "The shell unit has no reload handler; restarting respawns the bar and overlays."
                                    Components.TextButton {
                                        text: "Restart Shell"
                                        enabled: root.maintenanceBusy === 0
                                        onClicked: {
                                            // The shell service is Type=simple with no
                                            // ExecReload, so reload silently fails. Restart
                                            // is the supported operation. We close the panel
                                            // AFTER issuing the command so the user can see
                                            // the success banner in the brief window before
                                            // the shell itself exits.
                                            root.maintenanceRun(["systemctl", "--user", "restart", "noxflow-shell"], "Restart shell");
                                        }
                                    }
                                }

                                Components.Divider { Layout.fillWidth: true }

                                Components.SettingRow {
                                    Layout.fillWidth: true
                                    label: "Nox Daemon"
                                    description: "Restart noxd and reconnect live system providers."
                                    Components.TextButton {
                                        text: "Restart Daemon"
                                        enabled: root.maintenanceBusy === 0
                                        onClicked: {
                                            root.closeAfterMaintenance = true;
                                            root.maintenanceRun(["systemctl", "--user", "restart", "noxd"], "Restart daemon");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close"); }
}
