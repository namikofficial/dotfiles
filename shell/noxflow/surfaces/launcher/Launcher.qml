// Universal Launcher — fuzzy-search application/window/command overlay.
// Super+Space to open. Modes: Apps, Windows, Commands, Calculator, Ask AI, Clipboard.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var hyprland
    property var clipboardModel: null

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress

    Behavior on openProgress {
        NumberAnimation { duration: Theme.Tokens.duration(lifecycle.animDuration); easing.type: lifecycle.easingType }
    }

    signal requestCaptureAfterClose()

    readonly property var modes: ["Apps", "Windows", "Commands", "Calc", "Ask AI", "Clipboard"]
    property int activeMode: 0
    property string searchText: ""
    property var filteredResults: []
    property int selectedIndex: 0

    property Process launchProcess: Process { command: []; running: false }

    // AI
    property string aiQuery: ""; property string aiResponse: ""; property bool aiLoading: false
    property int aiStatus: 0; property string aiErrorDetail: ""
    readonly property string aiEndpoint: Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/v1/chat/completions"
    readonly property string aiModel: Quickshell.env("NOXFLOW_AI_MODEL") || "qwen3-4b-local"
    readonly property int aiTimeoutMs: 30000
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    // Nerd Font icon map
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
    readonly property string defaultIcon: "\uF15B"

    readonly property var emptyLabels: [
        "No applications found", "No open windows", "No matching commands",
        "", "Ask anything\u2026", "No clipboard history"
    ]

    // Scrim: ultra-light, blurs background
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.15)
        opacity: lifecycle.active ? 1 : 0
        TapHandler { onTapped: lifecycle.requestClose("clickOutside") }
    }

    // Centered card
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width * 0.55, Theme.Tokens.scaled(580))
        height: Math.min(root.height * 0.6, Theme.Tokens.scaled(480))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault; border.width: 1
        scale: root.reducedMotion ? 1.0 : 0.9 + 0.1 * lifecycle.openProgress
        opacity: lifecycle.openProgress

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // Search field
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                Components.TextField {
                    id: searchField; Layout.fillWidth: true; label: ""; showClearButton: true
                    focus: lifecycle.interactive
                    placeholderText: root.activeMode === 4 ? "Ask anything\u2026" : "Search apps, windows, commands\u2026"
                    onTextChanged: { root.searchText = text; if (root.activeMode === 4) { root.aiQuery = text; root.triggerAiQuery(); } root.filterResults(); }
                    Keys.onDownPressed: root.moveList(1); Keys.onUpPressed: root.moveList(-1)
                    Keys.onReturnPressed: root.activateSelected(); Keys.onEscapePressed: lifecycle.requestClose("escape")
                    Keys.onTabPressed: function(e) { root.activeMode = (root.activeMode+1) % root.modes.length; root.resetAi(); root.filterResults(); e.accepted = true; }
                }
            }
            // Mode tabs
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingXs
                Repeater {
                    model: root.modes
                    delegate: Rectangle {
                        required property int index; required property string modelData
                        Layout.fillWidth: true; height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusPill
                        color: root.activeMode === index ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: root.activeMode === index ? Theme.Tokens.tonalPrimary : "transparent"
                        border.width: root.activeMode === index ? 1 : 0
                        Text { anchors.centerIn: parent; text: modelData
                            color: root.activeMode === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelMedium; font.family: Theme.Tokens.typographyFontFamily }
                        TapHandler { onTapped: { root.activeMode = index; root.filterResults(); searchField.forceActiveFocus(); } }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
            Components.Divider { Layout.fillWidth: true }

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
                        Text { Layout.fillWidth: true; visible: root.aiStatus === 3 && root.aiErrorDetail !== ""
                            text: root.aiErrorDetail; color: Theme.Tokens.stateDanger; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.WordWrap }
                        Flickable { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentHeight: aiText.height; visible: !root.aiLoading && root.aiResponse !== ""
                            Text { id: aiText; width: parent.width; text: root.aiResponse
                                color: root.aiStatus === 3 ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium; wrapMode: Text.WordWrap }
                        }
                        Text { Layout.fillWidth: true; visible: !root.aiLoading && (root.aiStatus === 2 || root.aiStatus === 3)
                            text: "via " + root.aiModel; color: Theme.Tokens.textDisabled
                            font.pixelSize: Theme.Tokens.typographyLabelSmall; horizontalAlignment: Text.AlignRight }
                    }
                }
                // Empty state
                Text { anchors.centerIn: parent
                    text: root.searchText !== "" ? "No results"
                          : root.activeMode === 4 ? root.emptyLabels[4]
                          : root.activeMode === 3 ? "Type an expression\u2026"
                          : root.emptyLabels[root.activeMode] || "Type to search\u2026"
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: root.filteredResults.length === 0 && !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading)) }
                // Results list
                ListView { id: resultsList; anchors.fill: parent; model: root.filteredResults; currentIndex: root.selectedIndex
                    spacing: Theme.Tokens.spacingXs; visible: !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))
                    delegate: Item {
                        required property int index; required property var modelData
                        width: parent ? parent.width : 0; height: Theme.Tokens.scaled(Theme.Tokens.heightControl)
                        property bool ho: false; property bool pr: false
                        readonly property bool cur: index === root.selectedIndex
                        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: cur ? Theme.Tokens.tonalPrimaryContainer : ho ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: Theme.Tokens.spacingMd
                            Text { text: modelData.icon || root.defaultIcon; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd; font.family: "Symbols Nerd Font Mono" }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.title || modelData.name || "Unknown"; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.subtitle || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; visible: text !== "" }
                            }
                            Text { text: modelData.shortcut || ""; color: cur ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; visible: text !== "" }
                        }
                        TapHandler { onPressedChanged: parent.pr = pressed; onTapped: { root.selectedIndex = index; root.activateSelected(); } }
                        HoverHandler { onHoveredChanged: parent.ho = hovered; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
    }

    anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() { resetAi(); searchText = ""; searchField.text = ""; activeMode = 0; filteredResults = []; selectedIndex = 0; filterResults(); }
        function onClosed() { if (lifecycle.closeReason === "screenshot") root.requestCaptureAfterClose(); }
    }

    // AI
    property var aiXhr: null; property string pendingAiQuery: ""
    Timer { id: aiTimer; repeat: false; interval: 400; onTriggered: root.executeAiQuery(root.pendingAiQuery) }
    Timer { id: aiTimeout; repeat: false; interval: root.aiTimeoutMs; onTriggered: root.handleAiTimeout() }
    function handleAiTimeout() { if (!aiLoading) return; if (aiXhr) { aiXhr.abort(); aiXhr = null; } aiLoading = false; aiStatus = 3; aiResponse = "AI request timed out"; aiErrorDetail = "Check that the AI endpoint is reachable."; }
    function triggerAiQuery() { var q = searchText.trim(); if (q.length < 3) { if (aiStatus !== 0) resetAi(); return; } if (aiXhr) { aiXhr.abort(); aiXhr = null; } pendingAiQuery = q; aiTimer.restart(); }
    function executeAiQuery(query) { aiLoading = true; aiStatus = 1; aiResponse = ""; aiErrorDetail = ""; var xhr = new XMLHttpRequest(); aiXhr = xhr; xhr.open("POST", aiEndpoint, true); xhr.setRequestHeader("Content-Type", "application/json"); xhr.timeout = aiTimeoutMs; xhr.ontimeout = function() { aiXhr = null; aiLoading = false; aiStatus = 3; aiResponse = "AI request timed out"; }; xhr.onreadystatechange = function() { if (xhr.readyState !== XMLHttpRequest.DONE) return; aiTimeout.stop(); aiXhr = null; aiLoading = false; if (xhr.status === 200) { try { var j = JSON.parse(xhr.responseText); aiResponse = j.choices?.[0]?.message?.content || "No response"; aiStatus = 2; } catch(e) { aiResponse = "Failed to parse AI response"; aiStatus = 3; } } else if (xhr.status === 0) { aiResponse = "AI endpoint unreachable"; aiErrorDetail = "Ensure llama.cpp (or your provider) is running at " + aiEndpoint; aiStatus = 3; } else { aiResponse = "AI request failed (HTTP " + xhr.status + ")"; aiStatus = 3; } }; aiTimeout.start(); xhr.send(JSON.stringify({ model: aiModel, messages: [{ role: "system", content: "You are a helpful assistant. Answer concisely." }, { role: "user", content: query }], temperature: 0.7, max_tokens: 512, stream: false })); }
    function resetAi() { aiQuery = ""; aiResponse = ""; aiLoading = false; aiStatus = 0; aiErrorDetail = ""; aiTimeout.stop(); if (aiXhr) { aiXhr.abort(); aiXhr = null; } }

    // Result sources
    property var appCache: []
    property bool scanStarted: false
    property string desktopBuffer: ""
    property Process desktopScanner: Process { id: desktopScanner; running: false
        stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.desktopBuffer += data; } }
        onExited: function() { if (root.desktopBuffer) { root.parseDesktopFiles(root.desktopBuffer); root.desktopBuffer = ""; root.filterResults(); } }
    }
    function scanDesktopFiles() { if (scanStarted) return; scanStarted = true; desktopScanner.command = ["sh","-c","find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | head -200 | while read f; do name=$(grep -m1 '^Name=' \"$f\" 2>/dev/null | cut -d= -f2-); exec=$(grep -m1 '^Exec=' \"$f\" 2>/dev/null | cut -d= -f2- | sed 's/ .*//' | sed 's/%[a-zA-Z]//g'); icon=$(grep -m1 '^Icon=' \"$f\" 2>/dev/null | cut -d= -f2-); [ -n \"$name\" ] && [ -n \"$exec\" ] && echo \"$name|$exec|$icon\"; done | sort -u"]; desktopScanner.running = true; }
    function parseDesktopFiles(data) { if (!data) return; var lines = data.trim().split("\n"); var apps = []; for (var i = 0; i < lines.length; i++) { var p = lines[i].split("|"); if (p.length < 2) continue; var title = p[0].trim(); var cmd = p[1].trim(); var basename = cmd.split("/").pop().split(" ")[0].toLowerCase(); var icon = root.nerdMap[basename] || root.defaultIcon; if (title && cmd) apps.push({ title:title, icon:icon, subtitle:cmd, action:"launch", actionParams:{command:cmd} }); } appCache = apps.length > 0 ? apps : buildDefaultApps(); }
    function buildDefaultApps() {
        return [
            { title:"Dolphin", icon:root.nerdMap["dolphin"]||"\uF07C", subtitle:"File manager", action:"launch", actionParams:{command:"dolphin"}},
            { title:"Firefox", icon:root.nerdMap["firefox"]||"\uF269", subtitle:"Web browser", action:"launch", actionParams:{command:"firefox"}},
            { title:"Kitty", icon:root.nerdMap["kitty"]||"\uF120", subtitle:"Terminal", action:"launch", actionParams:{command:"kitty"}},
            { title:"Code", icon:root.nerdMap["code"]||"\uF121", subtitle:"VS Code", action:"launch", actionParams:{command:"code"}},
            { title:"Settings", icon:"\uF013", subtitle:"System settings", action:"launch", actionParams:{command:"gnome-control-center"}},
            { title:"Obsidian", icon:root.nerdMap["obsidian"]||"\uF044", subtitle:"Notes", action:"launch", actionParams:{command:"obsidian"}}
        ];
    }
    function filterResults() { if (activeMode === 0 && !root.scanStarted) { appCache = buildDefaultApps(); scanDesktopFiles(); } var q = searchText.toLowerCase().trim(); selectedIndex = 0; if (activeMode === 4) { filteredResults = []; return; } if (activeMode === 5) { if (!root.clipboardModel) { filteredResults = []; return; } var ci = root.clipboardModel.asLauncherItems(20); filteredResults = q === "" ? ci : ci.filter(function(i) { return i.title.toLowerCase().indexOf(q) >= 0; }); return; } if (activeMode === 3) { if (q === "") { filteredResults = []; return; } filteredResults = [{ title:"= "+evaluateCalc(q), icon:"\uF1EC", subtitle:q }]; return; } var src = activeMode === 0 ? buildAppResults() : activeMode === 1 ? buildWindowResults() : buildCommandResults(); if (q === "") { filteredResults = src.slice(0, 20); return; } var r = []; for (var i = 0; i < src.length; i++) { var item = src[i]; if (((item.title||"")+" "+(item.subtitle||"")).toLowerCase().indexOf(q) >= 0) { r.push(item); if (r.length >= 30) break; } } filteredResults = r; }
    function buildAppResults() { return appCache.length > 0 ? appCache : buildDefaultApps(); }
    function buildWindowResults() { if (!hyprland || !hyprland.windows) return []; return hyprland.windows.map(function(w) { return { title:w.title||"Untitled", icon:"\uF2D2", subtitle:w.workspace?"ws "+(w.workspace.name||w.workspace.id||""):"", action:"focus_window", actionParams:{address:w.address||""} }; }); }
    function buildCommandResults() { return [
        { title:"Lock", icon:"\uF023", subtitle:"Lock the screen", action:"lock", actionParams:{} },
        { title:"Suspend", icon:"\uF186", subtitle:"Suspend to RAM", action:"suspend", actionParams:{} },
        { title:"Reboot", icon:"\uF01E", subtitle:"Reboot the system", action:"reboot", actionParams:{} },
        { title:"Power Off", icon:"\uF011", subtitle:"Shut down", action:"power_off", actionParams:{} },
        { title:"Dolphin", icon:"\uF07C", subtitle:"Open file manager", action:"launch", actionParams:{command:"dolphin"} },
        { title:"Screenshot", icon:"\uF030", subtitle:"Take a screenshot", action:"screenshot", actionParams:{} },
        { title:"Reload shell", icon:"\uF021", subtitle:"Reload NoxFlow shell", action:"reload_shell", actionParams:{} }
    ]; }

    // Safe calculator
    function evaluateCalc(expr) { try { var tokens = []; var num = ""; for (var i = 0; i < expr.length; i++) { var ch = expr[i]; if (/[0-9.]/.test(ch)) { num += ch; continue; } if (num) { tokens.push({t:"num",v:parseFloat(num)}); num = ""; } if (ch === ' ') continue; if ('+-*/()%'.indexOf(ch) >= 0) { tokens.push({t:ch,v:ch}); continue; } } if (num) tokens.push({t:"num",v:parseFloat(num)}); if (tokens.length === 0) return "?"; var pos = 0; function peek() { return pos < tokens.length ? tokens[pos] : null; } function consume() { return pos < tokens.length ? tokens[pos++] : null; } function parseExpr() { var left = parseTerm(); while (peek() && (peek().t === '+' || peek().t === '-')) { var op = consume().v; var right = parseTerm(); left = op === '+' ? left + right : left - right; } return left; } function parseTerm() { var left = parseFactor(); while (peek() && (peek().t === '*' || peek().t === '/' || peek().t === '%')) { var op = consume().v; var right = parseFactor(); if (op === '*') left *= right; else if (op === '/') { if (right === 0) throw "div0"; left /= right; } else left %= right; } return left; } function parseFactor() { if (peek() && peek().t === '-') { consume(); return -parseFactor(); } if (peek() && peek().t === '(') { consume(); var val = parseExpr(); if (peek() && peek().t === ')') consume(); return val; } var tok = consume(); if (!tok || tok.t !== "num") throw "bad"; return tok.v; } var result = parseExpr(); if (typeof result === "number" && isFinite(result)) return String(Math.round(result*100)/100); return "?"; } catch(e) { return "?"; } }
    function moveList(d) { if (filteredResults.length === 0) return; selectedIndex = (selectedIndex + d + filteredResults.length) % filteredResults.length; resultsList.currentIndex = selectedIndex; }
    function activateSelected() { if (selectedIndex < 0 || selectedIndex >= filteredResults.length) return; var item = filteredResults[selectedIndex]; if (!item || !item.action) return; switch (item.action) { case "launch": if (item.actionParams && item.actionParams.command) { launchProcess.command = ["sh","-c",item.actionParams.command]; launchProcess.running = true; } lifecycle.requestClose("action"); break; case "focus_window": if (root.noxd && root.noxd.connected && item.actionParams && item.actionParams.address) root.noxd.runAction({ window_focus: { address: item.actionParams.address } }); lifecycle.requestClose("action"); break; case "lock": if (root.noxd && root.noxd.connected) root.noxd.runAction({ lock: {} }); lifecycle.requestClose("action"); break; case "suspend": if (root.noxd && root.noxd.connected) root.noxd.runAction({ suspend: {} }); lifecycle.requestClose("action"); break; case "reboot": if (root.noxd && root.noxd.connected) root.noxd.runAction({ reboot: {} }); lifecycle.requestClose("action"); break; case "power_off": if (root.noxd && root.noxd.connected) root.noxd.runAction({ power_off: {} }); lifecycle.requestClose("action"); break; case "screenshot": lifecycle.requestClose("screenshot"); break; case "reload_shell": launchProcess.command = ["systemctl","--user","restart","noxflow-shell"]; launchProcess.running = true; lifecycle.requestClose("action"); break; default: if (root.noxd && root.noxd.connected) { var a = {}; a[item.action] = item.actionParams || {}; root.noxd.runAction(a); } lifecycle.requestClose("action"); break; } }
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
