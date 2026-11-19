// Nox Command — one searchable desktop canvas, opened with Super+Space.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import "../../theme" as Theme
import "../../config" as Config
import "../../components" as Components
import "../../CommandHistory.js" as CommandHistory

Item {
    id: root
    required property var noxd
    required property var hyprland
    property var clipboardModel: null
    // Shared AI client owned by shell.qml. Configured from noxd settings; this
    // surface no longer reads NOXFLOW_AI_* or holds its own XHR.
    property var aiClient: null

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }
    signal requestCaptureAfterClose()

    // Shell-local window focus. The launcher "Windows" mode lists hyprland
    // clients and activating one focuses it. There is no typed daemon action
    // for window focus — the daemon's hyprland provider publishes state but
    // does not own focus dispatch, and the noxd Action enum has no
    // `window_focus` variant. Dispatch directly via hyprctl.
    property Components.Command windowFocusProcess: Components.Command {
        label: "Focus window"
    }
    function focusWindowByAddress(address) {
        var addr = String(address || "").trim();
        if (!addr) return;
        // hyprctl rejects malformed addresses; only accept hex digits.
        if (!/^0x[0-9a-fA-F]+$/.test(addr)) return;
        windowFocusProcess.run(["hyprctl", "dispatch", "focuswindow", "address:" + addr]);
    }

    property int activeMode: 0
    property string searchText: ""
    property var filteredResults: []
    property int selectedIndex: 0
    readonly property var selectedResult: selectedIndex >= 0 && selectedIndex < filteredResults.length
        ? filteredResults[selectedIndex] : null
    property bool launchBusy: false
    property string launchError: ""
    property string launchTarget: ""
    property var recentCommandKeys: []
    property var queuedHistoryKeys: []
    property bool historyReady: false
    property bool historyWriteAgain: false
    property string pendingHistoryKey: ""
    readonly property string launcherHistoryPath: {
        var stateHome = Quickshell.env("XDG_STATE_HOME") || ""
        if (stateHome === "") stateHome = (Quickshell.env("HOME") || "") + "/.local/state"
        return stateHome + "/noxflow/launcher-history.json"
    }
    property Components.Command historyReader: Components.Command {
        label: "Read recent commands"
        onExited: function(exitCode) {
            var loaded = []
            if (exitCode === 0) {
                try {
                    var payload = JSON.parse(root.historyReader.output || "{}")
                    if (payload.schemaVersion === 1 && Array.isArray(payload.commands))
                        loaded = payload.commands
                } catch (e) { loaded = [] }
            }
            root.recentCommandKeys = CommandHistory.normalize(root.queuedHistoryKeys.concat(loaded))
            root.queuedHistoryKeys = []
            root.historyReady = true
            if (root.recentCommandKeys.length > 0) root.writeRecentCommands()
            root.filterResults()
        }
    }
    property Components.Command historyWriter: Components.Command {
        label: "Save recent commands"
        onExited: function(exitCode) {
            if (exitCode !== 0) console.warn(root.historyWriter.failureText())
            if (root.historyWriteAgain) {
                root.historyWriteAgain = false
                root.writeRecentCommands()
            }
        }
    }
    property Components.Command launchProcess: Components.Command {
        label: "Launch"
        onStarted: { root.launchBusy = true; root.launchError = "" }
        onExited: function(exitCode) {
            root.launchBusy = false
            if (exitCode === 0) {
                root.recordRecentKey(root.pendingHistoryKey)
                root.pendingHistoryKey = ""
                lifecycle.requestClose("action")
                return
            }
            root.pendingHistoryKey = ""
            // stderr is kept by Command, so the banner names the real cause.
            root.launchError = root.launchProcess.failureText();
            searchField.forceActiveFocus()
        }
    }
    property Components.Command copyResultProcess: Components.Command {
        label: "Copy calculation result"
        onExited: function(exitCode) {
            root.launchBusy = false
            if (exitCode === 0) lifecycle.requestClose("action")
            else {
                root.launchError = root.copyResultProcess.failureText()
                searchField.forceActiveFocus()
            }
        }
    }

    // AI state lives in the shared AiClient; see the adapter below.
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    readonly property var nerdMap: ({
        "firefox":"\uF269","chromium":"\uF268","google-chrome":"\uF268","kitty":"\uF120",
        "alacritty":"\uF120","wezterm":"\uF120","foot":"\uF120","dolphin":"\uF07C",
        "thunar":"\uF07C","nautilus":"\uF07C","code":"\uF121","codium":"\uF121",
        "obsidian":"\uF044","discord":"\uF086","telegram":"\uF086","spotify":"\uF001",
        "gimp":"\uF1FC","blender":"\uF1B2","steam":"\uF1B6","godot":"\uF11B",
        "libreoffice":"\uF15C","keepassxc":"\uF084","bitwarden":"\uF084",
        "vlc":"\uF001","mpv":"\uF001","konsole":"\uF120","gnome-terminal":"\uF120",
        "gedit":"\uF15C","evince":"\uF02D","zathura":"\uF02D","okular":"\uF02D",
        "virt-manager":"\uF108","gparted":"\uF0A0","gnome-disks":"\uF0A0",
        "obs-studio":"\uF030"
    })
    readonly property string defaultIcon: "\u25A3"

    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            resetAi(); launchError = ""; searchText = ""; searchField.text = "";
            activeMode = 0; filteredResults = []; selectedIndex = 0; scanStarted = false;
            filterResults();
            // The layer-shell window becomes keyboard-interactive in the same
            // frame as this lifecycle signal. Defer focus once so the actual
            // TextInput receives the first typed character without a click.
            Qt.callLater(function() { searchField.focusInput(); });
        }
        // Drop text focus as soon as the close starts: the layer surface loses
        // the keyboard seat when it hides, and a still-focused TextInput makes
        // Qt log "QWaylandTextInputv3::disableSurface ... is focused".
        function onClosing(reason) { searchField.releaseInput(); }
        function onClosed() {
            root.resetAi()
            if (lifecycle.closeReason === "screenshot") root.requestCaptureAfterClose()
        }
    }

    // The inline island host creates this component only when Super+Space is
    // requested. Open its lifecycle from inside the component as well as from
    // the Loader callback so construction order cannot leave a blank card.
    Component.onCompleted: {
        root.historyReader.run(["cat", root.launcherHistoryPath])
        root.open()
    }

    // NoxIsland supplies the launcher card and its pill-to-panel transition.
    // Drawing another card here would stack translucent surfaces and compete
    // with the single command canvas.
    Item {
        anchors.fill: parent
        opacity: lifecycle.openProgress

        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; spacing: Theme.Tokens.spacingMd
            // Search
            Components.TextField { id: searchField; Layout.fillWidth: true; label: ""; showClearButton: true
                focus: lifecycle.active
                placeholderText: root.activeMode === 5 ? "Ask anything\u2026" : "Search your desktop · ? to ask AI"
                onTextChanged: {
                    root.searchText = text
                    var ask = text.trim().charAt(0) === "?"
                    if (ask) {
                        root.activeMode = 5
                        root.aiQuery = text.trim().slice(1).trim()
                        root.triggerAiQuery()
                    } else {
                        if (root.activeMode === 5) root.resetAi()
                        root.activeMode = 0
                    }
                    root.filterResults()
                }
                onAccepted: root.activateSelected()
                onNavigateUp: root.moveList(-1)
                onNavigateDown: root.moveList(1)
                onNavigateHome: root.selectBoundary(false)
                onNavigateEnd: root.selectBoundary(true)
                Keys.onEscapePressed: lifecycle.requestClose("escape")
            }
            Text {
                Layout.fillWidth: true
                text: root.activeMode === 5
                    ? (root.aiAvailable ? "Ask NoxFlow · type a question" : "AI is not configured")
                    : root.searchText.trim() === "" && root.hasRecentResults()
                        ? "Recent commands first   ·   Apps   ·   Windows   ·   Projects   ·   Actions"
                        : "Apps   ·   Windows   ·   Projects   ·   Actions   ·   Calculations"
                color: Theme.Tokens.textMuted
                font.pixelSize: Theme.Tokens.typographyLabelMedium
                elide: Text.ElideRight
            }
            Components.Divider { Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true
                visible: root.launchBusy || root.scanBusy || root.projectScanBusy || root.launchError !== "" || root.scanError !== "" || root.projectScanError !== ""
                spacing: Theme.Tokens.spacingSm
                Text {
                    Layout.fillWidth: true
                    text: root.launchBusy ? "Opening " + root.launchTarget + "\u2026" : root.scanBusy ? "Loading applications\u2026" : root.projectScanBusy ? "Loading project contexts\u2026" : (root.launchError || root.scanError || root.projectScanError)
                    color: root.launchBusy || root.scanBusy || root.projectScanBusy ? Theme.Tokens.textMuted : Theme.Tokens.stateDanger
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    wrapMode: Text.WordWrap
                }
                Components.TextButton {
                    visible: (root.scanFailed && !root.scanBusy && root.scanError !== "")
                        || (!root.projectScanBusy && root.projectScanError !== "")
                    text: "Retry"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        if (root.projectScanError !== "") {
                            root.projectScanStarted = false
                            root.projectScanError = ""
                            root.scanProjects()
                        } else root.retryScan()
                    }
                }
            }
            // Results area
            Item { Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                // AI panel
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: Theme.Tokens.surfaceSurfaceContainer
                    visible: root.activeMode === 5 && (root.aiStatus > 0 || root.aiLoading)
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingSm
                        RowLayout { Layout.fillWidth: true; visible: root.aiLoading; spacing: Theme.Tokens.spacingSm
                            Components.LoadingIndicator {}
                            Text { text: "Thinking\u2026"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        }
                        Text { Layout.fillWidth: true; visible: root.aiStatus === 3 && root.aiErrorDetail !== ""; text: root.aiErrorDetail; color: Theme.Tokens.stateDanger; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.WordWrap }
                        Flickable { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentHeight: aiText.height; visible: !root.aiLoading && root.aiResponse !== ""
                            Text { id: aiText; width: parent.width; text: root.aiResponse
                                color: root.aiStatus === 3 ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium; wrapMode: Text.WordWrap } }
                        Text { Layout.fillWidth: true; visible: !root.aiLoading && (root.aiStatus === 2 || root.aiStatus === 3); text: "via " + root.aiModel; color: Theme.Tokens.textDisabled; font.pixelSize: Theme.Tokens.typographyLabelSmall; horizontalAlignment: Text.AlignRight }
                    }
                }
                // Empty
                Text { anchors.centerIn: parent
                    text: root.activeMode === 5 ? "Ask anything\u2026"
                        : root.projectScanStarted && !root.projectScanBusy
                            && root.projectScanError === "" && root.projectCache.length === 0
                            && /(project|session)/i.test(root.searchText)
                            ? "No project contexts are registered in Workbench"
                        : root.searchText !== "" ? "No matching actions"
                        : "Start typing to search"
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: root.filteredResults.length === 0 && !(root.activeMode === 5 && (root.aiResponse !== "" || root.aiLoading)) }
                // List
                ListView { id: resultsList
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.rightMargin: previewPane.visible ? previewPane.width + Theme.Tokens.spacingMd : 0
                    model: root.filteredResults; currentIndex: root.selectedIndex
                    spacing: Theme.Tokens.spacingXs; visible: !(root.activeMode === 5 && (root.aiResponse !== "" || root.aiLoading))
                    delegate: Item {
                        required property int index; required property var modelData
                        width: parent ? parent.width : 0; height: Theme.Tokens.scaled(56)
                        property bool ho: false; property bool pr: false
                        readonly property bool cur: index === root.selectedIndex
                        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: cur ? Theme.Tokens.tonalPrimaryContainer : ho ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                        Rectangle { visible: cur; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Theme.Tokens.scaled(3); height: Theme.Tokens.scaled(28); radius: width / 2; color: Theme.Tokens.tonalPrimary }
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: Theme.Tokens.spacingMd
                            Item { Layout.preferredWidth: Theme.Tokens.scaled(28); Layout.preferredHeight: Theme.Tokens.scaled(28)
                                // Plain Image with a bounded sourceSize: IconImage rasterised theme SVGs
                                // at their intrinsic size while its width was still 0 (the
                                // qt.svg.draw "buffer too big" spam), and counted a blank
                                // loading icon as visible, hiding the glyph fallback.
                                Image { id: appIcon; anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                                    sourceSize: Qt.size(Theme.Tokens.scaled(56), Theme.Tokens.scaled(56))
                                    source: root.openProgress > 0.5 ? root.iconSource(modelData) : ""; visible: status === Image.Ready }
                                Text { anchors.fill: parent; text: modelData.icon || root.defaultIcon; visible: !appIcon.visible; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd; font.family: Theme.Tokens.iconFont; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.title || modelData.name || "Unknown"; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: cur; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.subtitle || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; visible: text !== "" }
                            }
                            Text { text: modelData.shortcut || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; visible: text !== "" }
                        }
                        TapHandler { onPressedChanged: parent.pr = pressed; onTapped: { root.selectedIndex = index; root.activateSelected() } }
                        HoverHandler { onHoveredChanged: { parent.ho = hovered; if (hovered) root.selectedIndex = index } cursorShape: Qt.PointingHandCursor }
                    }
                }
                Rectangle {
                    id: previewPane
                    anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                    width: Theme.Tokens.scaled(220)
                    radius: Theme.Tokens.radiusMd
                    color: Theme.Tokens.surfaceSurfaceContainer
                    visible: root.activeMode !== 5 && root.selectedResult !== null
                    Accessible.name: root.selectedResult
                        ? "Preview: " + String(root.selectedResult.title || root.selectedResult.name || "Selected action")
                        : "Command preview"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingMd
                        spacing: Theme.Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingSm
                            Item {
                                Layout.preferredWidth: Theme.Tokens.scaled(36)
                                Layout.preferredHeight: Theme.Tokens.scaled(36)
                                Image {
                                    id: previewIcon
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    sourceSize: Qt.size(Theme.Tokens.scaled(72), Theme.Tokens.scaled(72))
                                    source: root.selectedResult ? root.iconSource(root.selectedResult) : ""
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.fill: parent
                                    text: root.selectedResult ? (root.selectedResult.icon || root.defaultIcon) : root.defaultIcon
                                    visible: !previewIcon.visible
                                    color: Theme.Tokens.tonalPrimary
                                    font.pixelSize: Theme.Tokens.iconLg
                                    font.family: Theme.Tokens.iconFont
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.previewActionLabel(root.selectedResult)
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.selectedResult
                                ? String(root.selectedResult.title || root.selectedResult.name || "Selected action")
                                : "Select a command"
                            color: Theme.Tokens.textPrimary
                            font.family: Theme.Tokens.typographyDisplayFamily
                            font.pixelSize: Theme.Tokens.typographyTitleMedium
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: root.selectedResult ? String(root.selectedResult.subtitle || "") : ""
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                        }
                        Components.Divider { Layout.fillWidth: true }
                        Text {
                            Layout.fillWidth: true
                            text: "↑ ↓  Select     Enter  Run\nEsc  Close"
                            color: Theme.Tokens.textMuted
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }
                    }
                }
            }
        }
    }

    // ── AI ──
    // Thin adapter over the shared services/AiClient.qml. The client owns the
    // endpoint, model, debounce, generation guard and timeout; this surface
    // only mirrors its state into the UI bindings that already exist.
    readonly property bool aiAvailable: !!aiClient && String(aiClient.endpoint || "") !== ""
    readonly property string aiEndpoint: aiClient ? aiClient.endpoint : ""
    readonly property string aiModel: aiClient ? aiClient.model : ""

    property string aiQuery: ""
    readonly property string aiResponse: aiClient ? aiClient.response : ""
    readonly property bool aiLoading: aiClient ? aiClient.loading : false
    readonly property int aiStatus: aiClient ? aiClient.status : 0
    readonly property string aiErrorDetail: aiClient ? aiClient.errorDetail : ""

    function triggerAiQuery() {
        aiQuery = searchText.trim().replace(/^\?\s*/, "");
        if (!aiClient) return
        if (aiQuery === "") aiClient.reset()
        else aiClient.query(aiQuery)
    }
    function resetAi() {
        aiQuery = "";
        if (aiClient) aiClient.reset();
    }

    // ── App scanning ──
    property var appCache: []; property bool scanStarted: false; property bool scanBusy: false
    property string scanError: ""
    property var projectCache: []
    property bool projectScanStarted: false
    property bool projectScanBusy: false
    property string projectScanError: ""
    // Retry button visible when last scan failed and we have defaults showing
    property bool scanFailed: false
    property Components.Command desktopScanner: Components.Command {
        label: "Application discovery"
        onStarted: { root.scanBusy = true; root.scanError = "" }
        onExited: function(exitCode) {
            root.scanBusy = false
            if (exitCode === 0 && root.desktopScanner.output) { root.parseDesktopFiles(root.desktopScanner.output); root.scanFailed = false; }
            else if (exitCode !== 0) { root.scanError = root.desktopScanner.failureText(); root.scanFailed = true; }
            else { root.scanError = "No applications were discovered"; root.scanFailed = true; }""
            root.filterResults()
        }
    }
    property Components.Command projectScanner: Components.Command {
        label: "Project discovery"
        onStarted: { root.projectScanBusy = true; root.projectScanError = "" }
        onExited: function(exitCode) {
            root.projectScanBusy = false
            if (exitCode !== 0) {
                root.projectScanError = root.projectScanner.failureText()
                root.projectCache = []
            } else {
                try {
                    var payload = JSON.parse(root.projectScanner.output || "{}")
                    root.projectCache = payload.schemaVersion === 1 && Array.isArray(payload.projects)
                        ? payload.projects : []
                    root.projectScanError = ""
                } catch (e) {
                    root.projectCache = []
                    root.projectScanError = "Project registry returned invalid data"
                }
            }
            root.filterResults()
        }
    }
    function scanDesktopFiles() {
        if (desktopScanner.running) return;
        scanStarted = true; scanFailed = false;
        desktopScanner.run([Quickshell.env("HOME") + "/.config/hypr/scripts/launcher.sh", "--list-json"]);
    }
    function retryScan() { if (desktopScanner.running) return; scanStarted = false; scanError = ""; scanDesktopFiles() }
    function scanProjects() {
        if (projectScanner.running || projectScanStarted) return
        projectScanStarted = true
        projectScanner.run([Quickshell.env("HOME") + "/Documents/code/dotfiles/setup/project-profile.sh", "list-json"])
    }
    function iconSource(item) {
        // launcher.sh resolves most icons to files; load those directly. The
        // image://icon provider below rasterises SVGs at an unbounded size
        // (qt.svg.draw warnings), so it is only the fallback.
        if (item && item.iconPath) return "file://" + item.iconPath;
        var iconName = item && item.iconName ? String(item.iconName).trim() : "";
        if (iconName === "") return "";
        if (iconName.charAt(0) === "/") return "file://" + iconName;
        try {
            if (!Quickshell.hasThemeIcon(iconName)) return "";
            return Quickshell.iconPath(iconName) || "";
        } catch (e) { return ""; }
    }
    function parseDesktopFiles(data) { if (!data) return; try { var records = data.trim().split("\n"); var apps = []; for (var i = 0; i < records.length; i++) { var r = JSON.parse(records[i]); var id = r.desktopId; var title = r.name; if (!id || !title) continue; var basename = id.replace(/\.desktop$/, "").toLowerCase(); apps.push({ title:title, iconName:r.icon || basename, iconPath:r.iconPath || "", icon:root.nerdMap[basename] || root.defaultIcon, subtitle:id, action:"launch", actionParams:{desktopId:id} }) } if (apps.length === 0) throw new Error("empty application list"); appCache = apps; scanError = "" } catch (e) { appCache = buildDefaultApps(); scanError = "Application discovery returned invalid data" } }
    // Fallback list used only when .desktop discovery fails. Every entry is a
    // shell action: `launchProgram` resolves through config/Apps.qml so a
    // missing binary reports why instead of failing silently. Settings is a
    // shell surface, not gnome-control-center (not installed).
    function buildDefaultApps() { return [{ title:"Dolphin", iconName:"org.kde.dolphin", icon:"\uF07C", subtitle:"File manager", action:"launchProgram", actionParams:{program:"files"} }, { title:"Firefox", iconName:"firefox", icon:"\uF269", subtitle:"Browser", action:"launchProgram", actionParams:{program:"browser"} }, { title:"Kitty", iconName:"kitty", icon:"\uF120", subtitle:"Terminal", action:"launchProgram", actionParams:{program:"terminal"} }, { title:"Code", iconName:"code", icon:"\uF121", subtitle:"VS Code", action:"launchProgram", actionParams:{program:"editor"} }, { title:"Settings", iconName:"preferences-system", icon:"\uF013", subtitle:"Settings", action:"open_settings", actionParams:{} }, { title:"Obsidian", iconName:"obsidian", icon:"\uF044", subtitle:"Notes", action:"launchProgram", actionParams:{program:"notes"} }] }

    // ── Filtering ──
    function matchScore(item, query) {
        var title = String(item.title || item.name || "").toLowerCase();
        var haystack = (title + " " + String(item.subtitle || "")).toLowerCase();
        if (query === "") return 0;
        var exact = title === query ? 1000 : 0;
        var prefix = title.indexOf(query) === 0 ? 500 : title.indexOf(query) >= 0 ? 250 : 0;
        var cursor = 0;
        for (var i = 0; i < query.length; i++) {
            var at = haystack.indexOf(query[i], cursor);
            if (at < 0) return -1;
            cursor = at + 1;
        }
        return exact + prefix + Math.max(0, 100 - cursor);
    }
    function previewActionLabel(item) {
        if (!item) return "No selection"
        if (item.action === "resume_project") return "Open project context"
        if (item.action === "project_action") {
            var command = item.actionParams ? String(item.actionParams.command || "") : ""
            return command === "edit" ? "Open project editor"
                : command === "shell" ? "Open project terminal"
                : command === "tmux" ? "Open project session" : "Project action"
        }
        if (item.action === "launch") return "Open application"
        if (item.action === "launchProgram") return "Run desktop action"
        if (item.action === "focus_window") return "Focus open window"
        if (item.action === "copy_result") return "Copy result to clipboard"
        if (item.action === "open_clipboard") return "Open clipboard history"
        if (item.action === "screenshot") return "Select a screenshot region"
        if (item.action === "open_settings") return "Open Nox Studio"
        return String(item.action || "Command").replace(/_/g, " ")
    }
    function recentPosition(item) {
        return historyReady ? CommandHistory.position(recentCommandKeys, item) : -1
    }
    function hasRecentResults() {
        if (!historyReady || recentCommandKeys.length === 0) return false
        for (var i = 0; i < filteredResults.length; i++) {
            if (recentPosition(filteredResults[i]) >= 0) return true
        }
        return false
    }
    function recordRecentKey(key) {
        if (!key) return
        if (!historyReady) {
            queuedHistoryKeys = CommandHistory.normalize([key].concat(queuedHistoryKeys))
            return
        }
        recentCommandKeys = CommandHistory.normalize([key].concat(recentCommandKeys))
        writeRecentCommands()
        filterResults()
    }
    function recordRecentCommand(item) {
        recordRecentKey(CommandHistory.keyFor(item))
    }
    function writeRecentCommands() {
        var payload = JSON.stringify({ schemaVersion: 1, commands: recentCommandKeys })
        if (historyWriter.running) {
            historyWriteAgain = true
            return
        }
        var script = "umask 077; dir=${1%/*}; mkdir -p -- \"$dir\" || exit 1; tmp=\"$dir/.launcher-history.$$\"; trap 'rm -f -- \"$tmp\"' EXIT; printf %s \"$2\" > \"$tmp\" && chmod 600 \"$tmp\" && mv -f -- \"$tmp\" \"$1\""
        historyWriter.run(["sh", "-c", script, "noxflow-history", launcherHistoryPath, payload])
    }
    function ranked(items, query, limit) {
        var scored = [];
        for (var i = 0; i < items.length; i++) {
            var score = matchScore(items[i], query);
            if (query === "" || score >= 0) scored.push({ item: items[i], score: score });
        }
        scored.sort(function(a, b) {
            if (query === "") {
                var aRecent = root.recentPosition(a.item)
                var bRecent = root.recentPosition(b.item)
                if (aRecent !== bRecent) {
                    if (aRecent < 0) return 1
                    if (bRecent < 0) return -1
                    return aRecent - bRecent
                }
            }
            var scoreDelta = b.score - a.score;
            if (scoreDelta !== 0) return scoreDelta;
            var aTitle = String(a.item.title || a.item.name || "");
            var bTitle = String(b.item.title || b.item.name || "");
            return aTitle.localeCompare(bTitle);
        });
        return scored.slice(0, limit || 30).map(function(entry) { return entry.item; });
    }
    function filterResults() {
        if (activeMode === 0 && !root.scanStarted) { appCache = buildDefaultApps(); scanDesktopFiles(); }
        if (activeMode === 0 && !root.projectScanStarted) scanProjects()
        var q = searchText.toLowerCase().trim();
        selectedIndex = 0;
        if (activeMode === 5) { filteredResults = []; return; }
        var src = buildAllResults()
        filteredResults = ranked(src, q, q === "" ? 20 : 30);
    }
    function buildAppResults() { return appCache.length > 0 ? appCache : buildDefaultApps() }
    function buildProjectResults() {
        var items = []
        projectCache.forEach(function(project) {
            if (!project || !project.id || !project.name) return
            var id = String(project.id)
            var prefix = String(project.name)
            var selectors = [id].concat(Array.isArray(project.aliases) ? project.aliases : []).join(" ")
            items.push({ title: prefix + " — Restore context", icon: "\uF07C",
                subtitle: "Project · " + selectors + " · editor, terminal, and saved tools", action: "resume_project",
                actionParams: { id: id } })
            items.push({ title: prefix + " — Open editor", icon: "\uF121",
                subtitle: "Project · " + selectors, action: "project_action",
                actionParams: { id: id, command: "edit" } })
            items.push({ title: prefix + " — Terminal", icon: "\uF120",
                subtitle: "Project · " + selectors, action: "project_action",
                actionParams: { id: id, command: "shell" } })
            items.push({ title: prefix + " — tmux session", icon: "\uF120",
                subtitle: "Project · " + selectors, action: "project_action",
                actionParams: { id: id, command: "tmux" } })
        })
        return items
    }
    function buildAllResults() {
        var items = buildAppResults().concat(buildWindowResults(), buildCommandResults(), buildProjectResults())
        items.push({ title: "Open clipboard history", icon: "\uF0EA",
            subtitle: "Clipboard · Search, copy, pin, and manage history",
            action:"open_clipboard", actionParams: {} })
        if (searchText.trim() !== "") {
            var expression = searchText.trim()
            var result = evaluateCalc(expression)
            if (result.valid) items.push({ title: "= " + result.display, icon: "\uF1EC",
                subtitle: "Calculation · " + expression, action: "copy_result",
                actionParams: { value: result.value } })
        }
        return items
    }
    function buildWindowResults() { try { if (!hyprland || !hyprland.windows) return []; var out = []; var wins = hyprland.windows; for (var i = 0; i < wins.length; i++) { var w = wins[i]; if (!w) continue; var wsLabel = ""; if (w.workspace) wsLabel = "ws " + (w.workspace.name || w.workspace.id || ""); out.push({ title:w.title||"Untitled", icon:"\uF2D2", subtitle:wsLabel, action:"focus_window", actionParams:{address:w.address||""} }) } return out } catch(e) { return [] } }
    function buildCommandResults() {
        return [
            { title: "Lock", icon: "\uF023", subtitle: "Lock the screen", action: "lock", actionParams: {} },
            { title: "Suspend", icon: "\uF186", subtitle: "Suspend to RAM", action: "suspend", actionParams: {} },
            { title: "Reboot", icon: "\uF01E", subtitle: "Reboot the system", action: "reboot", actionParams: {} },
            { title: "Power Off", icon: "\uF011", subtitle: "Shut down", action: "power_off", actionParams: {} },
            { title: "Screenshot", icon: "\uF030", subtitle: "Take a screenshot", action: "screenshot", actionParams: {} },
            { title: "Reload shell", icon: "\uF021", subtitle: "Restart NoxFlow shell", action: "reload_shell", actionParams: {} }
        ]
    }

    // Safe calculator with proper input validation.
    // Returns { valid: bool, display: string, value: number|string }.
    // display shows the human-readable result or error message.
    // value is only set for valid finite numbers (used for copy action).
    function evaluateCalc(expr) {
        // Reject obviously malformed queries before tokenizing
        if (!expr || expr.length === 0) return { valid: false, display: "?", value: "" };
        var ch, num = "", tokens = [];
        // Tokenize with strict character validation
        for (var i = 0; i < expr.length; i++) {
            ch = expr[i];
            if ((ch >= '0' && ch <= '9') || ch === '.') {
                num += ch;
                continue;
            }
            if (num) {
                var n = parseFloat(num);
            if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(num) || isNaN(n)) return { valid: false, display: "Invalid number", value: "" };
                tokens.push({ t: "num", v: n });
                num = "";
            }
            if (ch === ' ') continue;
            if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '(' || ch === ')' || ch === '%') {
                tokens.push({ t: ch, v: ch });
                continue;
            }
            // Unknown character — reject
            return { valid: false, display: "Invalid character", value: "" };
        }
        if (num) {
            var n2 = parseFloat(num);
        if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(num) || isNaN(n2)) return { valid: false, display: "Invalid number", value: "" };
            tokens.push({ t: "num", v: n2 });
            num = "";
        }
        if (tokens.length === 0) return { valid: false, display: "?", value: "" };

        var pos = 0;
        function peek() { return pos < tokens.length ? tokens[pos] : null; }
        function consume() { return pos < tokens.length ? tokens[pos++] : null; }

        // parseExpr → parseTerm → parseFactor with binary operators
        function parseExpr() {
            var left = parseTerm();
            while (peek() && (peek().t === '+' || peek().t === '-')) {
                var op = consume().v;
                var right = parseTerm();
                left = op === '+' ? left + right : left - right;
            }
            return left;
        }
        function parseTerm() {
            var left = parseFactor();
            while (peek() && (peek().t === '*' || peek().t === '/' || peek().t === '%')) {
                var op = consume().v;
                var right = parseFactor();
                if (op === '*') {
                    left *= right;
                } else if (op === '/') {
                    if (right === 0) throw new Error("div0");
                    left /= right;
                } else { // '%'
                    if (right === 0) throw new Error("mod0");
                    left = left % right;
                }
            }
            return left;
        }
        function parseFactor() {
            if (peek() && peek().t === '-') {
                consume();
                return -parseFactor();
            }
            if (peek() && peek().t === '(') {
                consume();
                var val = parseExpr();
                if (!peek() || peek().t !== ')') throw new Error("unclosed");
                consume(); // consume ')'
                return val;
            }
            var tok = consume();
            if (!tok || tok.t !== "num") throw new Error("bad");
            return tok.v;
        }

        try {
            var result = parseExpr();
            // Check for unconsumed tokens
            if (pos < tokens.length) throw new Error("unconsumed");
            if (typeof result !== "number" || !isFinite(result)) throw new Error("notfinite");
            var rounded = Math.round(result * 100) / 100;
            return { valid: true, display: String(rounded), value: rounded };
        } catch(e) {
            var msg = e.message || String(e);
            if (msg === "div0" || msg === "mod0") return { valid: false, display: "Division by zero", value: "" };
            if (msg === "unclosed") return { valid: false, display: "Unclosed parenthesis", value: "" };
            if (msg === "bad") return { valid: false, display: "Invalid expression", value: "" };
            if (msg === "unconsumed") return { valid: false, display: "Trailing operators", value: "" };
            if (msg === "notfinite") return { valid: false, display: "Invalid result", value: "" };
            return { valid: false, display: "?", value: "" };
        }
    }
    function moveList(d) { if (filteredResults.length === 0) return; selectedIndex = (selectedIndex + d + filteredResults.length) % filteredResults.length; resultsList.currentIndex = selectedIndex; resultsList.positionViewAtIndex(selectedIndex, ListView.Contain) }
    function selectBoundary(last) { if (filteredResults.length === 0) return; selectedIndex = last ? filteredResults.length - 1 : 0; resultsList.currentIndex = selectedIndex; resultsList.positionViewAtIndex(selectedIndex, ListView.Contain) }
    function activateSelected() {
        if (activeMode === 5) { triggerAiQuery(); return }
        if (launchBusy || selectedIndex < 0 || selectedIndex >= filteredResults.length) return
        var item = filteredResults[selectedIndex]
        if (!item || !item.action) return
        switch (item.action) {
        case "resume_project":
            if (!item.actionParams || !item.actionParams.id) return
            launchTarget = item.title || "project"
            launchError = ""
            launchProcess.label = "Open project context"
            pendingHistoryKey = CommandHistory.keyFor(item)
            if (!launchProcess.run([Quickshell.env("HOME") + "/.config/hypr/scripts/project-resume.sh",
                "restore", "--project", String(item.actionParams.id)])) pendingHistoryKey = ""
            break
        case "project_action":
            if (!item.actionParams || !item.actionParams.id
                    || ["edit", "shell", "tmux"].indexOf(item.actionParams.command) < 0) return
            Quickshell.execDetached([Quickshell.env("HOME")
                + "/Documents/code/dotfiles/setup/project-profile.sh",
                String(item.actionParams.command), String(item.actionParams.id)])
            recordRecentCommand(item)
            lifecycle.requestClose("action")
            break
        case "copy_result":
            if (!item.actionParams || item.actionParams.value === undefined) return
            launchBusy = true
            launchTarget = "result"
            copyResultProcess.run(["sh", "-c", "printf %s \"$1\" | wl-copy --type text/plain",
                "launcher", String(item.actionParams.value)])
            break
        case "launch":
            if (!item.actionParams) return
            launchTarget = item.title || "application"
            launchError = ""
            launchProcess.label = "Launch application"
            var argv;
            if (item.actionParams.desktopId) argv = ["uwsm", "app", "-t", "service", "--", item.actionParams.desktopId];
            else if (item.actionParams.command) argv = ["uwsm", "app", "-t", "service", "--", item.actionParams.command];
            if (argv) {
                pendingHistoryKey = CommandHistory.keyFor(item)
                if (!launchProcess.run(argv)) pendingHistoryKey = ""
            } else return;
            break
        case "launchProgram":
            // Registry-backed launch: availability was probed at startup, so a
            // missing binary reports the reason instead of failing silently.
            if (!item.actionParams || !item.actionParams.program) return
            launchTarget = item.title || "application"
            launchError = ""
            var launched = Config.Apps.invoke(item.actionParams.program, item.actionParams.args || [])
            if (launched.ok) {
                recordRecentCommand(item)
                lifecycle.requestClose("action")
            }
            else { launchError = launched.reason }
            break
        case "open_settings":
            // NoxFlow's own settings panel — not gnome-control-center, which
            // is not installed on this workstation.
            lifecycle.requestClose("openSettings")
            if (shellRoot && typeof shellRoot.openSettings === "function") {
                shellRoot.openSettings()
                recordRecentCommand(item)
            }
            break
        case "focus_window":
            // Shell-local: dispatch via hyprctl. No typed daemon action exists.
            if (item.actionParams && item.actionParams.address) root.focusWindowByAddress(item.actionParams.address);
            lifecycle.requestClose("action")
            break
        case "open_clipboard":
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/cliphist-rofi.sh"])
            recordRecentCommand(item)
            lifecycle.requestClose("action")
            break
        case "lock": if (root.noxd && root.noxd.connected) root.noxd.runAction({lock:{}}); lifecycle.requestClose("action"); break
        case "suspend": if (root.noxd && root.noxd.connected) root.noxd.runAction({suspend:{}}); lifecycle.requestClose("action"); break
        case "reboot": if (root.noxd && root.noxd.connected) root.noxd.runAction({reboot:{}}); lifecycle.requestClose("action"); break
        case "power_off": if (root.noxd && root.noxd.connected) root.noxd.runAction({power_off:{}}); lifecycle.requestClose("action"); break
        case "screenshot": recordRecentCommand(item); lifecycle.requestClose("screenshot"); break
        case "reload_shell":
            launchTarget = "NoxFlow"
            launchProcess.label = "Restart shell";
            launchProcess.run(["systemctl", "--user", "restart", "noxflow-shell.service"]);
            break
        default:
            if (root.noxd && root.noxd.connected) { var a = {}; a[item.action] = item.actionParams || {}; root.noxd.runAction(a) }
            lifecycle.requestClose("action")
            break
        }
    }

    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close") }
}
