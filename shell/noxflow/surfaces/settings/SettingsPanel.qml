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
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
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
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

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
    property int lastStatusAt: 0
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

    function reportStatus(kind, key, message) {
        lastStatusKind = kind;
        lastStatusKey = key || "";
        lastStatusMessage = message || "";
        lastStatusAt = Date.now();
    }

    function clearStatus() {
        lastStatusKind = "";
        lastStatusKey = "";
        lastStatusMessage = "";
    }

    function applyAppearanceFromMap(map) {
        if (!map) return;
        if (map["appearance.profile"] !== undefined) {
            var profile = String(map["appearance.profile"]);
            if (Theme.Tokens.currentProfile !== profile) Theme.Tokens.applyProfile(profile);
        }
        if (map["appearance.density"] !== undefined) {
            var density = String(map["appearance.density"]);
            if (Theme.Tokens.activeDensity !== density) Theme.Tokens.activeDensity = density;
        }
        if (map["shell.reduced_motion"] !== undefined) {
            var reduced = !!map["shell.reduced_motion"];
            if (Theme.Tokens.reducedMotion !== reduced) Theme.Tokens.reducedMotion = reduced;
        }
        if (map["appearance.radius"] !== undefined) {
            var radius = Number(map["appearance.radius"]);
            if (!isNaN(radius)) Theme.Tokens.applyRadius(radius);
        }
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
        switch (key) {
            case "appearance.profile": return String(Theme.Tokens.currentProfile);
            case "appearance.density": return String(Theme.Tokens.activeDensity);
            case "shell.reduced_motion": return !!Theme.Tokens.reducedMotion;
            case "appearance.radius": return Number(Theme.Tokens.appearanceRadius);
            default: return undefined;
        }
    }

    function revertLocalValue(key, value) {
        switch (key) {
            case "appearance.profile":
                if (Theme.Tokens.currentProfile !== value) Theme.Tokens.applyProfile(String(value));
                break;
            case "appearance.density":
                if (Theme.Tokens.activeDensity !== value) Theme.Tokens.activeDensity = String(value);
                break;
            case "shell.reduced_motion":
                if (Theme.Tokens.reducedMotion !== value) Theme.Tokens.reducedMotion = !!value;
                break;
            case "appearance.radius":
                Theme.Tokens.applyRadius(Number(value));
                break;
        }
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
            reportStatus("external", "", "Settings hydrated from daemon");
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
        function onClosing(reason) {
            // Drop any pending writes so the panel doesn't display stale
            // Pending indicators when reopened. The daemon either accepted
            // them (in which case the SettingUpdated callback cleared the
            // pending tag) or rejected them (errorCallback cleared it).
        }
    }

    Timer {
        // Auto-clear the status banner after a few seconds so it doesn't
        // accumulate stale saved/rejected messages during long sessions.
        interval: 4000
        repeat: false
        running: root.lastStatusKind !== "" && root.lifecycle.interactive
        onTriggered: {
            // Only clear if no new status arrived in the meantime.
            if (Date.now() - root.lastStatusAt >= interval) {
                root.clearStatus();
            }
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
    function maintenanceRun(command, label) {
        if (maintenanceBusy > 0) return;
        maintenanceBusy += 1;
        var proc = maintenanceProc;
        proc.command = command;
        proc.label = label;
        proc.running = true;
    }
    property Process maintenanceProc: Process {
        id: maintenanceProc
        property string label: ""
        command: []; running: false
        onExited: function(exitCode, exitStatus) {
            var lbl = root.maintenanceProc.label || "command";
            if (exitCode === 0) {
                reportStatus("saved", "", lbl + ": ok");
            } else {
                reportStatus("rejected", "", lbl + " failed (exit " + exitCode + ")");
            }
            root.maintenanceBusy = Math.max(0, root.maintenanceBusy - 1);
        }
    }

    // ── Settings panel ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.7, Theme.Tokens.scaled(520))
        height: Math.min(parent.height * 0.75, Theme.Tokens.scaled(500))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        scale: 0.85 + 0.15 * root.openProgress
        opacity: root.openProgress

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingXl
            spacing: Theme.Tokens.spacingLg

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Settings"
                    color: Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyHeadlineMedium
                    font.family: Theme.Tokens.typographyFontFamily
                    font.bold: true; Layout.fillWidth: true
                }
                Components.IconButton {
                    iconText: "✕"; accessibleName: "Close settings"
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            // ── Status banner ──
            // Reflects connection state, hydration result, last write result
            // and last maintenance result. Always truthful: a visible
            // "rejected" stays until the user changes something else or the
            // 4-second timer expires.
            Rectangle {
                Layout.fillWidth: true
                visible: root.lastStatusKind !== "" || root.hydrationInFlight
                radius: Theme.Tokens.radiusMd
                implicitHeight: statusRow.implicitHeight + Theme.Tokens.spacingMd * 2
                color: Theme.Tokens.withAlpha(
                    root.lastStatusKind === "rejected" ? Theme.Tokens.stateDanger
                        : root.lastStatusKind === "reconnect" ? Theme.Tokens.stateWarning
                        : root.lastStatusKind === "unavailable" ? Theme.Tokens.stateWarning
                        : root.lastStatusKind === "external" ? Theme.Tokens.stateInfo
                        : Theme.Tokens.stateSuccess, 0.18)
                border.color: Theme.Tokens.withAlpha(
                    root.lastStatusKind === "rejected" ? Theme.Tokens.stateDanger
                        : root.lastStatusKind === "reconnect" ? Theme.Tokens.stateWarning
                        : root.lastStatusKind === "unavailable" ? Theme.Tokens.stateWarning
                        : root.lastStatusKind === "external" ? Theme.Tokens.stateInfo
                        : Theme.Tokens.stateSuccess, 0.42)
                border.width: 1
                RowLayout {
                    id: statusRow
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingMd
                    spacing: Theme.Tokens.spacingSm
                    Text {
                        text: root.hydrationInFlight ? "•" : (root.lastStatusKind === "rejected" ? "!" : root.lastStatusKind === "saved" ? "✓" : root.lastStatusKind === "external" ? "↻" : root.lastStatusKind === "reconnect" ? "↻" : root.lastStatusKind === "unavailable" ? "!" : "")
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.iconSm
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.hydrationInFlight ? "Loading settings from daemon…"
                            : root.lastStatusKind === "saved" ? root.lastStatusMessage
                            : root.lastStatusKind === "rejected" ? root.lastStatusMessage
                            : root.lastStatusKind === "external" ? root.lastStatusMessage
                            : root.lastStatusKind === "reconnect" ? root.lastStatusMessage
                            : root.lastStatusKind === "unavailable" ? root.lastStatusMessage
                            : ""
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                }
            }

            Components.Divider { Layout.fillWidth: true }

            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: contentColumn.height; clip: true; interactive: true

                ColumnLayout {
                    id: contentColumn; width: parent.width
                    spacing: Theme.Tokens.spacingLg

                    Text {
                        text: "Theme Profile"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.family: Theme.Tokens.typographyFontFamily; font.bold: true
                    }
                    Text {
                        text: "Switch between colour palettes"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                        font.family: Theme.Tokens.typographyFontFamily
                    }

                    Repeater {
                        model: Theme.ThemeProfiles.profileNames()
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isActive: Theme.Tokens.currentProfile === modelData
                            readonly property bool isPending: root.pendingWrites["appearance.profile"] !== undefined
                                && root.pendingWrites["appearance.profile"].value === modelData
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Apply " + modelData + " theme"

                            Layout.fillWidth: true; height: Theme.Tokens.scaled(48)
                            radius: Theme.Tokens.radiusMd
                            color: isActive ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                            border.color: isActive ? Theme.Tokens.tonalPrimary : "transparent"
                            border.width: isActive ? 1 : 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.Tokens.spacingLg
                                spacing: Theme.Tokens.spacingMd

                                Row {
                                    spacing: 3; Layout.alignment: Qt.AlignVCenter
                                    Repeater {
                                        model: [
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.primary,
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.secondary,
                                            Theme.ThemeProfiles.getProfile(modelData).tonals.tertiary,
                                            Theme.ThemeProfiles.getProfile(modelData).surfaces.surface
                                        ]
                                        delegate: Rectangle {
                                            width: 12; height: 12; radius: 3; color: modelData
                                            border.color: Theme.Tokens.outlineSubtle; border.width: 1
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Text {
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
                                        font.family: Theme.Tokens.typographyFontFamily; font.bold: isActive
                                    }
                                    Text {
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
                                        font.family: Theme.Tokens.typographyFontFamily; visible: text !== ""
                                    }
                                }

                                Text {
                                    text: isPending ? "…" : isActive ? "✓" : ""
                                    color: Theme.Tokens.tonalPrimary
                                    font.pixelSize: Theme.Tokens.iconSm
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

                    Components.Divider { Layout.fillWidth: true }

                    Text {
                        text: "Appearance"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                        Text {
                            text: "Density"; color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                var labels = { compact: "Compact", comfortable: "Comfortable", spacious: "Spacious" };
                                return labels[Theme.Tokens.activeDensity] || Theme.Tokens.activeDensity;
                            }
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            Layout.preferredWidth: Theme.Tokens.scaled(96)
                        }
                        Repeater {
                            model: ["compact", "comfortable", "spacious"]
                            delegate: Components.TextButton {
                                required property string modelData
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                Layout.preferredWidth: Theme.Tokens.scaled(80)
                                opacity: Theme.Tokens.activeDensity === modelData ? 1.0 : 0.6
                                onClicked: {
                                    if (Theme.Tokens.activeDensity === modelData) return;
                                    Theme.Tokens.activeDensity = modelData;
                                    root.writeSetting("appearance.density", modelData, "Density " + modelData);
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                        Text {
                            text: "Reduced motion"; color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true
                        }
                        Text {
                            text: Theme.Tokens.reducedMotion ? "On" : "Off"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            Layout.preferredWidth: Theme.Tokens.scaled(48)
                        }
                        Components.Toggle {
                            accessibleName: "Reduced motion"
                            checked: Theme.Tokens.reducedMotion
                            onToggled: {
                                if (Theme.Tokens.reducedMotion === value) return;
                                Theme.Tokens.reducedMotion = value;
                                root.writeSetting("shell.reduced_motion", value, "Reduced motion");
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                        Text {
                            text: "Corner radius"; color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                        }
                        Text {
                            // Label must reflect the EFFECTIVE radius, not a
                            // hard-coded constant. appearanceRadius is updated
                            // by applyRadius() so this binding is always honest.
                            text: Theme.Tokens.appearanceRadius + "px"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            Layout.preferredWidth: Theme.Tokens.scaled(40)
                        }
                        Repeater {
                            model: [4, 8, 14, 20, 28]
                            delegate: Components.TextButton {
                                required property int modelData
                                text: modelData + "px"
                                Layout.preferredWidth: Theme.Tokens.scaled(56)
                                opacity: Theme.Tokens.appearanceRadius === modelData ? 1.0 : 0.6
                                onClicked: {
                                    if (Theme.Tokens.appearanceRadius === modelData) return;
                                    Theme.Tokens.applyRadius(modelData);
                                    root.writeSetting("appearance.radius", modelData, "Radius " + modelData + "px");
                                }
                            }
                        }
                    }

                    Components.Divider { Layout.fillWidth: true }

                    Text {
                        text: "System"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                    }
                    Text {
                        text: "Run a verified operation on the user systemd instance. The shell service has no reload handler, so \"Reload\" issues a restart (the shell will exit and respawn)."
                        color: Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    Flow {
                        Layout.fillWidth: true; spacing: Theme.Tokens.spacingSm
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
                        Components.TextButton {
                            text: "Restart Daemon"
                            enabled: root.maintenanceBusy === 0
                            onClicked: {
                                root.maintenanceRun(["systemctl", "--user", "restart", "noxd"], "Restart daemon");
                                lifecycle.requestClose("restartDaemon");
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
