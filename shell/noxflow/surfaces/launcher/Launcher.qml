// Universal Launcher — Super+Space. Modes: Apps, Windows, Commands, Calc, Ask AI, Clipboard.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    required property var noxd
    required property var hyprland
    property var clipboardModel: null

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: Theme.Tokens.duration(lifecycle.animDuration); easing.type: lifecycle.easingType } }
    signal requestCaptureAfterClose()

    readonly property var modes: ["Apps","Windows","Commands","Calc","Ask AI","Clipboard"]
    property int activeMode: 0
    property string searchText: ""
    property var filteredResults: []
    property int selectedIndex: 0
    property bool launchBusy: false
    property string launchError: ""
    property string launchStderr: ""
    property string launchTarget: ""
    property Process launchProcess: Process {
        command: []; running: false
        stderr: SplitParser { splitMarker: ""; onRead: function(data) { root.launchStderr += data } }
        onStarted: { root.launchBusy = true; root.launchError = "" }
        onExited: function(exitCode, exitStatus) {
            root.launchBusy = false
            if (exitCode === 0) {
                lifecycle.requestClose("action")
                return
            }
            var detail = root.launchStderr.trim()
            root.launchError = "Could not launch " + root.launchTarget + " (exit " + exitCode + ")" + (detail ? ": " + detail : "")
            searchField.forceActiveFocus()
        }
    }

    // AI
    property string aiQuery: ""
    property string aiResponse: ""
    property bool aiLoading: false
    property int aiStatus: 0
    property string aiErrorDetail: ""
    readonly property string aiEndpoint: Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/v1/chat/completions"
    readonly property string aiModel: Quickshell.env("NOXFLOW_AI_MODEL") || "qwen3-4b-local"
    readonly property int aiTimeoutMs: 30000
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
        "gnome-control-center":"\uF013","obs-studio":"\uF030"
    })
    readonly property string defaultIcon: "\u25A3"
    readonly property var emptyLabels: ["No applications found","No open windows","No matching commands","","Ask anything\u2026","No clipboard history"]

    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() { resetAi(); launchError = ""; searchText = ""; searchField.text = ""; activeMode = 0; filteredResults = []; selectedIndex = 0; scanStarted = false; filterResults(); searchField.forceActiveFocus() }
        function onClosed() { if (lifecycle.closeReason === "screenshot") root.requestCaptureAfterClose() }
    }

    // The inline island host creates this component only when Super+Space is
    // requested. Open its lifecycle from inside the component as well as from
    // the Loader callback so construction order cannot leave a blank card.
    Component.onCompleted: root.open()

    // NoxIsland supplies the launcher card and its pill-to-panel transition.
    // Drawing another card here would stack translucent surfaces and reduce
    // the usable width enough to truncate mode labels.
    Item {
        anchors.fill: parent
        opacity: lifecycle.openProgress

        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; spacing: Theme.Tokens.spacingMd
            // Search
            Components.TextField { id: searchField; Layout.fillWidth: true; label: ""; showClearButton: true
                placeholderText: root.activeMode === 4 ? "Ask anything\u2026" : "Search\u2026"
                onTextChanged: { root.searchText = text; if (root.activeMode === 4) { root.aiQuery = text; root.triggerAiQuery() } root.filterResults() }
                onAccepted: root.activateSelected()
                onNavigateUp: root.moveList(-1)
                onNavigateDown: root.moveList(1)
                onNavigateHome: root.selectBoundary(false)
                onNavigateEnd: root.selectBoundary(true)
                Keys.onEscapePressed: lifecycle.requestClose("escape")
                Keys.onTabPressed: function(e) { root.activeMode = (root.activeMode + 1) % root.modes.length; root.resetAi(); root.filterResults(); e.accepted = true }
            }
            // Tabs
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.scaled(2)
                Repeater { model: root.modes
                    delegate: Rectangle { required property int index; required property string modelData
                        Layout.fillWidth: true; Layout.minimumWidth: 0; height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusPill
                        activeFocusOnTab: true; Accessible.role: Accessible.Button; Accessible.name: modelData + " launcher mode"
                        color: root.activeMode === index ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: root.activeMode === index ? Theme.Tokens.tonalPrimary : "transparent"; border.width: root.activeMode === index ? 1 : 0
                        Text { anchors.fill: parent; anchors.leftMargin: Theme.Tokens.scaled(3); anchors.rightMargin: Theme.Tokens.scaled(3); text: modelData; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            color: root.activeMode === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelSmall }
                        TapHandler { onTapped: { parent.forceActiveFocus(); root.activeMode = index; root.resetAi(); root.filterResults() } }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        Keys.onReturnPressed: { root.activeMode = index; root.resetAi(); root.filterResults() }
                        Keys.onSpacePressed: { root.activeMode = index; root.resetAi(); root.filterResults() }
                    }
                }
            }
            Components.Divider { Layout.fillWidth: true }
            Text {
                Layout.fillWidth: true
                visible: root.launchBusy || root.scanBusy || root.launchError !== "" || root.scanError !== ""
                text: root.launchBusy ? "Opening " + root.launchTarget + "\u2026" : root.scanBusy ? "Loading applications\u2026" : (root.launchError || root.scanError)
                color: root.launchBusy ? Theme.Tokens.textMuted : Theme.Tokens.stateDanger
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                wrapMode: Text.WordWrap
            }
            // Results area
            Item { Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                // AI panel
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: Theme.Tokens.surfaceSurfaceContainer
                    visible: root.activeMode === 4 && (root.aiStatus > 0 || root.aiLoading)
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
                    text: root.searchText !== "" ? "No results"
                        : root.activeMode === 4 ? root.emptyLabels[4]
                        : root.activeMode === 3 ? "Type an expression\u2026"
                        : root.emptyLabels[root.activeMode] || "Type to search\u2026"
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: root.filteredResults.length === 0 && !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading)) }
                // List
                ListView { id: resultsList; anchors.fill: parent; model: root.filteredResults; currentIndex: root.selectedIndex
                    spacing: Theme.Tokens.spacingXs; visible: !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))
                    delegate: Item {
                        required property int index; required property var modelData
                        width: parent ? parent.width : 0; height: Theme.Tokens.scaled(Theme.Tokens.heightControl)
                        property bool ho: false; property bool pr: false
                        readonly property bool cur: index === root.selectedIndex
                        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: cur ? Theme.Tokens.tonalPrimaryContainer : ho ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: Theme.Tokens.spacingMd
                            Item { Layout.preferredWidth: Theme.Tokens.scaled(28); Layout.preferredHeight: Theme.Tokens.scaled(28)
                                IconImage { id: appIcon; anchors.fill: parent; source: root.openProgress > 0.5 ? root.iconSource(modelData) : ""; visible: source !== "" && status !== Image.Error }
                                Text { anchors.fill: parent; text: modelData.icon || root.defaultIcon; visible: !appIcon.visible; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd; font.family: "Symbols Nerd Font Mono"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.title || modelData.name || "Unknown"; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.subtitle || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; visible: text !== "" }
                            }
                            Text { text: modelData.shortcut || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; visible: text !== "" }
                        }
                        TapHandler { onPressedChanged: parent.pr = pressed; onTapped: { root.selectedIndex = index; root.activateSelected() } }
                        HoverHandler { onHoveredChanged: parent.ho = hovered; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
    }

    // ── AI ──
    property var aiXhr: null; property string pendingAiQuery: ""
    Timer { id: aiTimer; repeat: false; interval: 400; onTriggered: root.executeAiQuery(root.pendingAiQuery) }
    Timer { id: aiTimeout; repeat: false; interval: root.aiTimeoutMs; onTriggered: root.handleAiTimeout() }
    function handleAiTimeout() { if (!aiLoading) return; if (aiXhr) { aiXhr.abort(); aiXhr = null } aiLoading = false; aiStatus = 3; aiResponse = "AI request timed out" }
    function triggerAiQuery() { var q = searchText.trim(); if (q.length < 3) { if (aiStatus !== 0) resetAi(); return } if (aiXhr) { aiXhr.abort(); aiXhr = null } pendingAiQuery = q; aiTimer.restart() }
    function executeAiQuery(query) { aiLoading = true; aiStatus = 1; aiResponse = ""; aiErrorDetail = ""; var xhr = new XMLHttpRequest(); aiXhr = xhr; xhr.open("POST", aiEndpoint, true); xhr.setRequestHeader("Content-Type", "application/json"); xhr.timeout = aiTimeoutMs; xhr.ontimeout = function() { aiXhr = null; aiLoading = false; aiStatus = 3; aiResponse = "AI timed out" }; xhr.onreadystatechange = function() { if (xhr.readyState !== XMLHttpRequest.DONE) return; aiTimeout.stop(); aiXhr = null; aiLoading = false; if (xhr.status === 200) { try { var j = JSON.parse(xhr.responseText); aiResponse = j.choices?.[0]?.message?.content || "No response"; aiStatus = 2 } catch(e) { aiResponse = "Failed to parse AI response"; aiStatus = 3 } } else if (xhr.status === 0) { aiResponse = "AI endpoint unreachable"; aiErrorDetail = "Ensure llama.cpp is running at " + aiEndpoint; aiStatus = 3 } else { aiResponse = "AI request failed (HTTP " + xhr.status + ")"; aiStatus = 3 } }; aiTimeout.start(); xhr.send(JSON.stringify({ model: aiModel, messages: [{ role: "system", content: "You are a helpful assistant. Answer concisely." }, { role: "user", content: query }], temperature: 0.7, max_tokens: 512, stream: false })) }
    function resetAi() { aiQuery = ""; aiResponse = ""; aiLoading = false; aiStatus = 0; aiErrorDetail = ""; aiTimeout.stop(); if (aiXhr) { aiXhr.abort(); aiXhr = null } }

    // ── App scanning ──
    property var appCache: []; property bool scanStarted: false; property bool scanBusy: false
    property string scanError: ""; property string desktopBuffer: ""; property string scannerStderr: ""
    property Process desktopScanner: Process { id: desktopScanner; running: false
        stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.desktopBuffer += data } }
        stderr: SplitParser { splitMarker: ""; onRead: function(data) { root.scannerStderr += data } }
        onStarted: { root.scanBusy = true; root.scanError = "" }
        onExited: function(exitCode, exitStatus) {
            root.scanBusy = false
            if (exitCode === 0 && root.desktopBuffer) root.parseDesktopFiles(root.desktopBuffer)
            else if (exitCode !== 0) root.scanError = "Application discovery failed" + (root.scannerStderr.trim() ? ": " + root.scannerStderr.trim() : "")
            else root.scanError = "No applications were discovered"
            root.desktopBuffer = ""
            root.scannerStderr = ""
            root.filterResults()
        }
    }
    function scanDesktopFiles() { if (scanStarted || desktopScanner.running) return; scanStarted = true; desktopBuffer = ""; scannerStderr = ""; desktopScanner.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/launcher.sh", "--list-json"]; desktopScanner.running = true }
    function iconSource(item) {
        var iconName = item && item.iconName ? String(item.iconName).trim() : "";
        if (iconName === "") return "";
        if (iconName.charAt(0) === "/") return "file://" + iconName;
        try {
            if (!Quickshell.hasThemeIcon(iconName)) return "";
            return Quickshell.iconPath(iconName) || "";
        } catch (e) { return ""; }
    }
    function parseDesktopFiles(data) { if (!data) return; try { var records = data.trim().split("\n"); var apps = []; for (var i = 0; i < records.length; i++) { var r = JSON.parse(records[i]); var id = r.desktopId; var title = r.name; if (!id || !title) continue; var basename = id.replace(/\.desktop$/, "").toLowerCase(); apps.push({ title:title, iconName:r.icon || basename, icon:root.nerdMap[basename] || root.defaultIcon, subtitle:id, action:"launch", actionParams:{desktopId:id} }) } if (apps.length === 0) throw new Error("empty application list"); appCache = apps; scanError = "" } catch (e) { appCache = buildDefaultApps(); scanError = "Application discovery returned invalid data" } }
    function buildDefaultApps() { return [{ title:"Dolphin", iconName:"org.kde.dolphin", icon:"\uF07C", subtitle:"File manager", action:"launch", actionParams:{command:"dolphin"} }, { title:"Firefox", iconName:"firefox", icon:"\uF269", subtitle:"Browser", action:"launch", actionParams:{command:"firefox"} }, { title:"Kitty", iconName:"kitty", icon:"\uF120", subtitle:"Terminal", action:"launch", actionParams:{command:"kitty"} }, { title:"Code", iconName:"code", icon:"\uF121", subtitle:"VS Code", action:"launch", actionParams:{command:"code"} }, { title:"Settings", iconName:"gnome-settings", icon:"\uF013", subtitle:"Settings", action:"launch", actionParams:{command:"gnome-control-center"} }, { title:"Obsidian", iconName:"obsidian", icon:"\uF044", subtitle:"Notes", action:"launch", actionParams:{command:"obsidian"} }] }

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
    function ranked(items, query, limit) {
        var scored = [];
        for (var i = 0; i < items.length; i++) {
            var score = matchScore(items[i], query);
            if (query === "" || score >= 0) scored.push({ item: items[i], score: score });
        }
        scored.sort(function(a, b) {
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
        var q = searchText.toLowerCase().trim();
        selectedIndex = 0;
        if (activeMode === 4) { filteredResults = []; return; }
        if (activeMode === 5) {
            var clipboardItems = [{ title:"Open Author Clipboard", iconName:"com.namikofficial.author-clipboard", icon:"\uF0EA", subtitle:"Search, copy, paste, pin, and manage history", action:"open_clipboard", actionParams:{} }];
            filteredResults = ranked(clipboardItems, q, 1); return;
        }
        if (activeMode === 3) {
            if (q === "") { filteredResults = []; return; }
            filteredResults = [{ title:"= " + evaluateCalc(q), icon:"\uF1EC", subtitle:q, action:"copy_result", actionParams:{value:evaluateCalc(q)} }]; return;
        }
        var src = activeMode === 0 ? buildAppResults() : activeMode === 1 ? buildWindowResults() : buildCommandResults();
        filteredResults = ranked(src, q, q === "" ? 20 : 30);
    }
    function buildAppResults() { return appCache.length > 0 ? appCache : buildDefaultApps() }
    function buildWindowResults() { try { if (!hyprland || !hyprland.windows) return []; var out = []; var wins = hyprland.windows; for (var i = 0; i < wins.length; i++) { var w = wins[i]; if (!w) continue; var wsLabel = ""; if (w.workspace) wsLabel = "ws " + (w.workspace.name || w.workspace.id || ""); out.push({ title:w.title||"Untitled", icon:"\uF2D2", subtitle:wsLabel, action:"focus_window", actionParams:{address:w.address||""} }) } return out } catch(e) { return [] } }
    function buildCommandResults() { return [{ title:"Lock", icon:"\uF023", subtitle:"Lock the screen", action:"lock", actionParams:{} }, { title:"Suspend", icon:"\uF186", subtitle:"Suspend to RAM", action:"suspend", actionParams:{} }, { title:"Reboot", icon:"\uF01E", subtitle:"Reboot the system", action:"reboot", actionParams:{} }, { title:"Power Off", icon:"\uF011", subtitle:"Shut down", action:"power_off", actionParams:{} }, { title:"Dolphin", icon:"\uF07C", subtitle:"Open file manager", action:"launch", actionParams:{command:"dolphin"} }, { title:"Screenshot", icon:"\uF030", subtitle:"Take a screenshot", action:"screenshot", actionParams:{} }, { title:"Reload shell", icon:"\uF021", subtitle:"Reload NoxFlow shell", action:"reload_shell", actionParams:{} }] }

    // Safe calculator
    function evaluateCalc(expr) { try { var tokens = []; var num = ""; for (var i = 0; i < expr.length; i++) { var ch = expr[i]; if (/[0-9.]/.test(ch)) { num += ch; continue } if (num) { tokens.push({t:"num",v:parseFloat(num)}); num = "" } if (ch === ' ') continue; if ('+-*/()%'.indexOf(ch) >= 0) { tokens.push({t:ch,v:ch}); continue } } if (num) tokens.push({t:"num",v:parseFloat(num)}); if (tokens.length === 0) return "?"; var pos = 0; function peek() { return pos < tokens.length ? tokens[pos] : null } function consume() { return pos < tokens.length ? tokens[pos++] : null } function parseExpr() { var left = parseTerm(); while (peek() && (peek().t === '+' || peek().t === '-')) { var op = consume().v; var right = parseTerm(); left = op === '+' ? left+right : left-right } return left } function parseTerm() { var left = parseFactor(); while (peek() && (peek().t === '*' || peek().t === '/' || peek().t === '%')) { var op = consume().v; var right = parseFactor(); if (op === '*') left *= right; else if (op === '/') { if (right === 0) throw "div0"; left /= right } else left %= right } return left } function parseFactor() { if (peek() && peek().t === '-') { consume(); return -parseFactor() } if (peek() && peek().t === '(') { consume(); var val = parseExpr(); if (peek() && peek().t === ')') consume(); return val } var tok = consume(); if (!tok || tok.t !== "num") throw "bad"; return tok.v } var result = parseExpr(); if (typeof result === "number" && isFinite(result)) return String(Math.round(result*100)/100); return "?" } catch(e) { return "?" } }
    function moveList(d) { if (filteredResults.length === 0) return; selectedIndex = (selectedIndex + d + filteredResults.length) % filteredResults.length; resultsList.currentIndex = selectedIndex; resultsList.positionViewAtIndex(selectedIndex, ListView.Contain) }
    function selectBoundary(last) { if (filteredResults.length === 0) return; selectedIndex = last ? filteredResults.length - 1 : 0; resultsList.currentIndex = selectedIndex; resultsList.positionViewAtIndex(selectedIndex, ListView.Contain) }
    function activateSelected() {
        if (launchBusy || selectedIndex < 0 || selectedIndex >= filteredResults.length) return
        var item = filteredResults[selectedIndex]
        if (!item || !item.action) return
        switch (item.action) {
        case "launch":
            if (!item.actionParams) return
            launchTarget = item.title || "application"
            launchStderr = ""
            launchError = ""
            if (item.actionParams.desktopId) launchProcess.command = ["gtk-launch", item.actionParams.desktopId]
            else if (item.actionParams.command) launchProcess.command = [item.actionParams.command]
            else return
            launchProcess.running = true
            break
        case "focus_window":
            if (root.noxd && root.noxd.connected && item.actionParams && item.actionParams.address) root.noxd.runAction({window_focus:{address:item.actionParams.address}})
            lifecycle.requestClose("action")
            break
        case "open_clipboard":
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/cliphist-rofi.sh"])
            lifecycle.requestClose("action")
            break
        case "lock": if (root.noxd && root.noxd.connected) root.noxd.runAction({lock:{}}); lifecycle.requestClose("action"); break
        case "suspend": if (root.noxd && root.noxd.connected) root.noxd.runAction({suspend:{}}); lifecycle.requestClose("action"); break
        case "reboot": if (root.noxd && root.noxd.connected) root.noxd.runAction({reboot:{}}); lifecycle.requestClose("action"); break
        case "power_off": if (root.noxd && root.noxd.connected) root.noxd.runAction({power_off:{}}); lifecycle.requestClose("action"); break
        case "screenshot": lifecycle.requestClose("screenshot"); break
        case "reload_shell":
            launchTarget = "NoxFlow"
            launchStderr = ""
            launchProcess.command = ["systemctl", "--user", "restart", "noxflow-shell.service"]
            launchProcess.running = true
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
