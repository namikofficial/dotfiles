// Universal Launcher — fuzzy-search application/window/command overlay.
// Super+Space to open. Modes: Apps, Windows, Commands, Calculator, Ask AI, Clipboard.
//
// Nerd Font icons via Symbols Nerd Font Mono (set in MaterialIcon component).

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

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress

    Behavior on openProgress {
        NumberAnimation { duration: Theme.Tokens.duration(lifecycle.animDuration); easing.type: lifecycle.easingType
            onRunningChanged: if (!running && Theme.Tokens.duration(lifecycle.animDuration) === 0 && lifecycle.state !== SurfaceLifecycle.State.Closed) lifecycle.finalize()
        }
    }

    signal requestCaptureAfterClose()

    // ── Modes ──
    readonly property var modes: ["Apps", "Windows", "Commands", "Calc", "Ask AI", "Clipboard"]
    property int activeMode: 0
    property string searchText: ""
    property var filteredResults: []
    property int selectedIndex: 0

    // ── Shared Process for launcher actions ──
    property Process launchProcess: Process { command: []; running: false }

    // ── AI mode state ──
    property string aiQuery: ""
    property string aiResponse: ""
    property bool aiLoading: false
    property int aiStatus: 0 // 0=idle, 1=loading, 2=done, 3=error
    property string aiErrorDetail: ""
    readonly property string aiEndpoint: Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/v1/chat/completions"
    readonly property string aiModel: Quickshell.env("NOXFLOW_AI_MODEL") || "qwen3-4b-local"
    readonly property int aiTimeoutMs: 30000

    // ── Reduced motion ──
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    // ── Nerd Font icon map (desktop file basename → Nerd Font glyph) ──
    readonly property var nerdIconMap: {
        // Browsers
        "firefox": "\uF269", "firefox-esr": "\uF269", "librewolf": "\uF269",
        "chromium": "\uF268", "chromium-browser": "\uF268", "google-chrome": "\uF268",
        // Terminals
        "kitty": "\uF120", "alacritty": "\uF120", "wezterm": "\uF120", "foot": "\uF120", "konsole": "\uF120", "gnome-terminal": "\uF120", "urxvt": "\uF120",
        // File managers
        "thunar": "\uF07C", "nautilus": "\uF07C", "dolphin": "\uF07C", "pcmanfm": "\uF07C", "ranger": "\uF07C",
        // Editors / IDEs
        "code": "\uF121", "codium": "\uF121", "code-oss": "\uF121", "neovim": "\uF121", "vim": "\uF121", "nvim": "\uF121", "gedit": "\uF15C",
        // Notes
        "obsidian": "\uF044", "logseq": "\uF044",
        // Chat
        "discord": "\uF086", "vesktop": "\uF086", "telegram": "\uF086", "element": "\uF086", "slack": "\uF086",
        // Media
        "spotify": "\uF001", "ncmpcpp": "\uF001", "mpd": "\uF001", "vlc": "\uF001", "celluloid": "\uF001", "mpv": "\uF001",
        // Graphics
        "gimp": "\uF1FC", "inkscape": "\uF1FC", "krita": "\uF1FC",
        // 3D
        "blender": "\uF1B2",
        // Gaming
        "godot": "\uF11B", "steam": "\uF1B6", "lutris": "\uF1B6", "heroic": "\uF1B6", "gamescope": "\uF11B",
        // Office
        "libreoffice": "\uF15C", "onlyoffice": "\uF15C", "evince": "\uF02D", "zathura": "\uF02D", "okular": "\uF02D",
        // Security
        "keepassxc": "\uF084", "bitwarden": "\uF084",
        // Virtualization
        "virt-manager": "\uF108", "gnome-boxes": "\uF108",
        // Disk utilities
        "gparted": "\uF0A0", "gnome-disks": "\uF0A0",
        // Settings
        "gnome-control-center": "\uF013", "gnome-settings": "\uF013", "lxappearance": "\uF013",
        // Misc
        "obs-studio": "\uF030"
    }
    readonly property string defaultIcon: "\uF15B" // nf-fa-file-o

    // ── Mode empty state labels ──
    readonly property var emptyStateLabels: [
        "No applications found\u2026",  // Apps
        "No open windows",              // Windows
        "No matching commands",          // Commands
        "",                              // Calc (no empty state)
        "Ask anything\u2026",            // Ask AI
        "No clipboard history"          // Clipboard
    ]

    // ── Window setup (compact centered panel) ──
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            resetAi();
            searchText = "";
            searchField.text = "";
            activeMode = 0;
            filteredResults = [];
            selectedIndex = 0;
            filterResults();
        }
        function onClosed() {
            if (lifecycle.closeReason === "screenshot") root.requestCaptureAfterClose();
        }
    }

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
    }

    // ── Scrim (lighter, with blur) ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.3)
        opacity: lifecycle.active ? 1 : 0
        TapHandler { onTapped: lifecycle.requestClose("clickOutside") }
    }

    // ── Search panel ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width * 0.6, Theme.Tokens.scaled(600))
        height: Math.min(root.height * 0.7, Theme.Tokens.scaled(500))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        scale: root.reducedMotion ? 1.0 : 0.85 + 0.15 * (lifecycle.openProgress)
        opacity: lifecycle.openProgress

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // ── Search field ──
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd
                Components.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    label: ""; showClearButton: true
                    focus: lifecycle.interactive
                    placeholderText: root.activeMode === 4 ? "Ask anything\u2026" : "Search apps, windows, commands\u2026"
                    onTextChanged: { root.searchText = text; if (root.activeMode === 4) { root.aiQuery = text; root.triggerAiQuery(); } root.filterResults(); }
                    Keys.onDownPressed: root.navigateList(1)
                    Keys.onUpPressed: root.navigateList(-1)
                    Keys.onReturnPressed: root.activateSelected()
                    Keys.onEscapePressed: lifecycle.requestClose("escape")
                    Keys.onTabPressed: function(event) { root.activeMode = (root.activeMode + 1) % root.modes.length; root.resetAi(); root.filterResults(); event.accepted = true; }
                }
                Rectangle { visible: root.filteredResults.length > 0; height: Theme.Tokens.scaled(20); implicitWidth: countText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingSm); radius: Theme.Tokens.radiusPill; color: Theme.Tokens.tonalPrimaryContainer
                    Text { id: countText; anchors.centerIn: parent; text: root.filteredResults.length + " results"; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true }
                }
            }

            // ── Mode tabs ──
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingXs
                Repeater {
                    model: root.modes
                    delegate: Rectangle {
                        required property int index; required property string modelData
                        Layout.fillWidth: true; height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusPill
                        color: root.activeMode === index ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: root.activeMode === index ? Theme.Tokens.tonalPrimary : "transparent"
                        border.width: root.activeMode === index ? 1 : 0
                        Text { anchors.centerIn: parent; text: modelData; color: root.activeMode === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelMedium; font.family: Theme.Tokens.typographyFontFamily }
                        TapHandler { onTapped: { root.activeMode = index; root.filterResults(); searchField.forceActiveFocus(); } }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Results area ──
            Item { Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                // AI response panel
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: Theme.Tokens.surfaceSurfaceContainer; visible: root.activeMode === 4 && (root.aiStatus > 0 || root.aiLoading)
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingSm
                        // Loading indicator row
                        RowLayout { Layout.fillWidth: true; visible: root.aiLoading; spacing: Theme.Tokens.spacingSm
                            Components.LoadingIndicator {}
                            Text { text: "Thinking\u2026"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall; font.family: Theme.Tokens.typographyFontFamily }
                            Item { Layout.fillWidth: true }
                            Text { text: root.aiQuery; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.maximumWidth: Theme.Tokens.scaled(200) }
                        }
                        // Error detail
                        Text { Layout.fillWidth: true; visible: root.aiStatus === 3 && root.aiErrorDetail !== ""; text: root.aiErrorDetail; color: Theme.Tokens.stateDanger; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.family: Theme.Tokens.typographyFontFamily; wrapMode: Text.WordWrap }
                        // Response text
                        Flickable { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentHeight: aiText.height; visible: !root.aiLoading && root.aiResponse !== ""
                            Text { id: aiText; width: parent.width; text: root.aiResponse; color: root.aiStatus === 3 ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.family: Theme.Tokens.typographyFontFamily; wrapMode: Text.WordWrap; textFormat: Text.RichText; onLinkActivated: function(link) { Qt.openUrlExternally(link); } }
                        }
                        // Model name footer
                        Text { Layout.fillWidth: true; visible: !root.aiLoading && (root.aiStatus === 2 || root.aiStatus === 3); text: "via " + root.aiModel; color: Theme.Tokens.textDisabled; font.pixelSize: Theme.Tokens.typographyLabelSmall; horizontalAlignment: Text.AlignRight }
                    }
                }

                // Empty / no-results state
                Text {
                    anchors.centerIn: parent
                    text: {
                        if (root.searchText !== "") return "No results"
                        if (root.activeMode === 4) return root.emptyStateLabels[4]
                        if (root.activeMode === 3) return "Type an expression\u2026"
                        return root.emptyStateLabels[root.activeMode] || "Type to search\u2026"
                    }
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    font.family: Theme.Tokens.typographyFontFamily
                    visible: root.filteredResults.length === 0 && !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))
                }

                // Results list
                ListView { id: resultsList; anchors.fill: parent; model: root.filteredResults; currentIndex: root.selectedIndex; spacing: Theme.Tokens.spacingXs; visible: !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))
                    delegate: FocusScope {
                        required property int index; required property var modelData
                        width: parent ? parent.width : 0; height: Theme.Tokens.scaled(Theme.Tokens.heightControl)

                        property bool hovered: false
                        property bool pressed: false
                        readonly property bool current: index === root.selectedIndex

                        // Background
                        Rectangle {
                            anchors.fill: parent; radius: Theme.Tokens.radiusSm
                            color: current ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        }

                        // State layer for hover/press (radius computed from parent)
                        Components.StateLayer {
                            target: parent
                            hovered: parent.hovered
                            pressed: parent.pressed
                        }

                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: Theme.Tokens.spacingMd
                            Text {
                                text: modelData.icon || root.defaultIcon
                                color: current ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.tonalPrimary
                                font.pixelSize: Theme.Tokens.iconMd
                                font.family: "Symbols Nerd Font Mono"
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.title || modelData.name || "Unknown"; color: current ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.subtitle || modelData.description || modelData.comment || ""; color: current ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                            }
                            Text { text: modelData.shortcut || ""; color: current ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; visible: text !== "" }
                        }
                        TapHandler {
                            onPressedChanged: parent.pressed = pressed
                            onTapped: { root.selectedIndex = index; root.activateSelected(); }
                        }
                        HoverHandler { onHoveredChanged: parent.hovered = hovered; cursorShape: Qt.PointingHandCursor }
                        Keys.onReturnPressed: root.activateSelected()
                        Keys.onSpacePressed: root.activateSelected()
                    }
                }
            }
        }
    }

    // ── AI HTTP client ──
    property var aiXhr: null
    property string pendingAiQuery: ""
    property Timer aiTimer: Timer { id: aiTimer; repeat: false; interval: 400; onTriggered: root.executeAiQuery(root.pendingAiQuery) }
    property Timer aiTimeout: Timer { id: aiTimeout; repeat: false; interval: root.aiTimeoutMs; onTriggered: root.handleAiTimeout() }

    function handleAiTimeout() {
        if (!aiLoading) return;
        if (aiXhr) { aiXhr.abort(); aiXhr = null; }
        aiLoading = false;
        aiStatus = 3;
        aiResponse = "AI request timed out after " + Math.round(aiTimeoutMs / 1000) + "s";
        aiErrorDetail = "Check that " + aiEndpoint + " is reachable and the model \u201c" + aiModel + "\u201d is available.";
    }

    function triggerAiQuery() {
        var query = searchText.trim();
        if (query.length < 3) { if (aiStatus !== 0) resetAi(); return; }
        if (aiXhr) { aiXhr.abort(); aiXhr = null; }
        pendingAiQuery = query; aiTimer.restart();
    }

    function executeAiQuery(query) {
        aiLoading = true; aiStatus = 1; aiResponse = ""; aiErrorDetail = "";
        var xhr = new XMLHttpRequest(); aiXhr = xhr;
        xhr.open("POST", aiEndpoint, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = aiTimeoutMs;
        xhr.ontimeout = function() {
            aiXhr = null; aiLoading = false; aiStatus = 3;
            aiResponse = "AI request timed out";
            aiErrorDetail = "The endpoint at " + aiEndpoint + " did not respond within " + Math.round(aiTimeoutMs / 1000) + "s.";
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            aiTimeout.stop();
            aiXhr = null; aiLoading = false;
            if (xhr.status === 200) {
                try { var json = JSON.parse(xhr.responseText); var text = json.choices && json.choices.length > 0 ? json.choices[0].message.content : "No response"; aiResponse = text; aiStatus = 2; }
                catch (e) { aiResponse = "Failed to parse AI response"; aiErrorDetail = "Invalid JSON from endpoint"; aiStatus = 3; }
            } else if (xhr.status === 0) {
                aiResponse = "AI endpoint unreachable";
                aiErrorDetail = "Could not connect to " + aiEndpoint + ". Ensure llama.cpp (or your provider) is running.";
                aiStatus = 3;
            } else {
                aiResponse = "AI request failed (HTTP " + xhr.status + ")";
                aiErrorDetail = "The endpoint returned an error status.";
                aiStatus = 3;
            }
        };
        aiTimeout.start();
        var body = JSON.stringify({ model: aiModel, messages: [{ role: "system", content: "You are a helpful assistant. Answer concisely and accurately." }, { role: "user", content: query }], temperature: 0.7, max_tokens: 512, stream: false });
        xhr.send(body);
    }

    function resetAi() { aiQuery = ""; aiResponse = ""; aiLoading = false; aiStatus = 0; aiErrorDetail = ""; aiTimeout.stop(); if (aiXhr) { aiXhr.abort(); aiXhr = null; } }

    // ── Result sources ──
    property var appCache: []
    property bool scanStarted: false
    property string desktopBuffer: ""
    property bool scanLoading: false
    property Process desktopScanner: Process { id: desktopScanner; running: false; stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.desktopBuffer += data; } }
        onExited: function(code, status) { root.scanLoading = false; if (root.desktopBuffer) { root.parseDesktopFiles(root.desktopBuffer); root.desktopBuffer = ""; root.filterResults(); } }
    }

    function scanDesktopFiles() {
        if (scanStarted) return; scanStarted = true; scanLoading = true;
        desktopScanner.command = ["sh", "-c", "find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | head -200 | while read f; do name=$(grep -m1 '^Name=' \"$f\" 2>/dev/null | cut -d= -f2-); exec=$(grep -m1 '^Exec=' \"$f\" 2>/dev/null | cut -d= -f2- | sed 's/ .*//' | sed 's/%[a-zA-Z]//g'); icon=$(grep -m1 '^Icon=' \"$f\" 2>/dev/null | cut -d= -f2-); [ -n \"$name\" ] && [ -n \"$exec\" ] && echo \"$name|$exec|$icon\"; done | sort -u"];
        desktopScanner.running = true;
    }

    function parseDesktopFiles(data) {
        if (!data) return;
        var lines = data.trim().split("\n"); var apps = [];
        for (var i = 0; i < lines.length; i++) { var parts = lines[i].split("|"); if (parts.length < 2) continue; var title = parts[0].trim(); var cmd = parts[1].trim(); var iconName = parts.length > 2 ? parts[2].trim().toLowerCase() : ""; var basename = cmd.split("/").pop().split(" ")[0].toLowerCase(); var icon = root.nerdIconMap[basename] || root.nerdIconMap[cmd] || root.nerdIconMap[iconName] || root.defaultIcon; if (!title || !cmd) continue; apps.push({ title: title, icon: icon, subtitle: cmd, action: "launch", actionParams: { command: cmd } }); }
        appCache = apps.length > 0 ? apps : buildDefaultApps();
    }

    function buildDefaultApps() {
        return [
            { title:"Firefox", icon:root.nerdIconMap["firefox"] || root.defaultIcon, subtitle:"Web browser", action:"launch", actionParams:{command:"firefox"}},
            { title:"Kitty", icon:root.nerdIconMap["kitty"] || root.defaultIcon, subtitle:"Terminal emulator", action:"launch", actionParams:{command:"kitty"}},
            { title:"Thunar", icon:root.nerdIconMap["thunar"] || root.defaultIcon, subtitle:"File manager", action:"launch", actionParams:{command:"thunar"}},
            { title:"Code", icon:root.nerdIconMap["code"] || root.defaultIcon, subtitle:"Visual Studio Code", action:"launch", actionParams:{command:"code"}},
            { title:"Settings", icon:"\uF013", subtitle:"System settings", action:"launch", actionParams:{command:"gnome-control-center"}},
            { title:"Obsidian", icon:root.nerdIconMap["obsidian"] || root.defaultIcon, subtitle:"Notes", action:"launch", actionParams:{command:"obsidian"}}
        ];
    }

    function filterResults() {
        if (activeMode === 0 && !root.scanStarted) { appCache = buildDefaultApps(); scanDesktopFiles(); }
        var query = searchText.toLowerCase().trim(); selectedIndex = 0;
        if (activeMode === 4) { filteredResults = []; return; }
        if (activeMode === 5) { if (!root.clipboardModel) { filteredResults = []; return; } var clipItems = root.clipboardModel.asLauncherItems(20); if (query === "") { filteredResults = clipItems; return; } filteredResults = clipItems.filter(function(item) { return item.title.toLowerCase().indexOf(query) >= 0; }); return; }
        if (activeMode === 3) { if (query === "") { filteredResults = []; return; } filteredResults = [{ title: "= " + evaluateCalc(query), icon: "\uF1EC", subtitle: query }]; return; }
        var source = activeMode === 0 ? buildAppResults() : activeMode === 1 ? buildWindowResults() : buildCommandResults();
        if (query === "") { filteredResults = source.slice(0, 20); return; }
        var results = []; for (var i = 0; i < source.length; i++) { var item = source[i]; var haystack = ((item.title || "") + " " + (item.subtitle || "") + " " + (item.description || "")).toLowerCase(); if (haystack.indexOf(query) >= 0) { results.push(item); if (results.length >= 30) break; } }
        filteredResults = results;
    }

    function buildAppResults() { return appCache.length > 0 ? appCache : buildDefaultApps(); }
    function buildWindowResults() { if (!hyprland || !hyprland.windows) return []; return hyprland.windows.map(function(w) { return { title:w.title||"Untitled", icon:"\uF2D2", subtitle:w.workspace?"ws "+(w.workspace.name||w.workspace.id||""):"", action:"focus_window", actionParams:{address:w.address||""} }; }); }
    function buildCommandResults() {
        return [
            { title:"Lock", icon:"\uF023", subtitle:"Lock the screen", action:"lock", actionParams:{} },
            { title:"Suspend", icon:"\uF186", subtitle:"Suspend to RAM", action:"suspend", actionParams:{} },
            { title:"Reboot", icon:"\uF01E", subtitle:"Reboot the system", action:"reboot", actionParams:{} },
            { title:"Power Off", icon:"\uF011", subtitle:"Shut down", action:"power_off", actionParams:{} },
            { title:"Toggle DND", icon:"\uF1F6", subtitle:"Do not disturb", action:"toggle_dnd", actionParams:{} },
            { title:"Screenshot", icon:"\uF030", subtitle:"Take a screenshot", action:"screenshot", actionParams:{} },
            { title:"Reload shell", icon:"\uF021", subtitle:"Reload NoxFlow shell", action:"reload_shell", actionParams:{} }
        ];
    }

    // ── Safe calculator evaluator ──
    // Uses a recursive-descent parser for basic arithmetic only.
    // No Function() / eval() — prevents code injection.
    function evaluateCalc(expr) {
        try {
            // Tokenize: numbers, operators, parens, whitespace
            var tokens = [];
            var num = "";
            for (var i = 0; i < expr.length; i++) {
                var ch = expr[i];
                if (/[0-9.]/.test(ch)) { num += ch; continue; }
                if (num) { tokens.push({ t: "num", v: parseFloat(num) }); num = ""; }
                if (ch === ' ') continue;
                if ('+-*/()%'.indexOf(ch) >= 0) { tokens.push({ t: ch, v: ch }); continue; }
                // Unknown character — skip
            }
            if (num) tokens.push({ t: "num", v: parseFloat(num) });

            if (tokens.length === 0) return "?";

            var pos = 0;
            function peek() { return pos < tokens.length ? tokens[pos] : null; }
            function consume() { return pos < tokens.length ? tokens[pos++] : null; }

            // Grammar: expr → term (('+'|'-') term)*
            function parseExpr() {
                var left = parseTerm();
                while (peek() && (peek().t === '+' || peek().t === '-')) {
                    var op = consume().v;
                    var right = parseTerm();
                    if (op === '+') left += right;
                    else left -= right;
                }
                return left;
            }

            // term → factor (('*'|'/'|'%') factor)*
            function parseTerm() {
                var left = parseFactor();
                while (peek() && (peek().t === '*' || peek().t === '/' || peek().t === '%')) {
                    var op = consume().v;
                    var right = parseFactor();
                    if (op === '*') left *= right;
                    else if (op === '/') { if (right === 0) throw "div0"; left /= right; }
                    else if (op === '%') left %= right;
                }
                return left;
            }

            // factor → '(' expr ')' | number | unary '-' factor
            function parseFactor() {
                if (peek() && peek().t === '-') { consume(); return -parseFactor(); }
                if (peek() && peek().t === '(') {
                    consume(); // '('
                    var val = parseExpr();
                    if (peek() && peek().t === ')') consume();
                    return val;
                }
                var tok = consume();
                if (!tok || tok.t !== "num") throw "bad";
                return tok.v;
            }

            var result = parseExpr();
            if (typeof result === "number" && isFinite(result)) return String(Math.round(result * 100) / 100);
            return "?";
        } catch (e) {
            return "?";
        }
    }

    function navigateList(delta) { if (filteredResults.length === 0) return; selectedIndex = (selectedIndex + delta + filteredResults.length) % filteredResults.length; resultsList.currentIndex = selectedIndex; }

    function activateSelected() {
        if (selectedIndex < 0 || selectedIndex >= filteredResults.length) return;
        var item = filteredResults[selectedIndex]; if (!item || !item.action) return;
        switch (item.action) {
            case "launch": if (item.actionParams && item.actionParams.command) { launchProcess.command = ["sh", "-c", item.actionParams.command]; launchProcess.running = true; } lifecycle.requestClose("action"); break;
            case "focus_window": if (root.noxd && root.noxd.connected && item.actionParams && item.actionParams.address) root.noxd.runAction({ window_focus: { address: item.actionParams.address } }); lifecycle.requestClose("action"); break;
            case "lock": if (root.noxd && root.noxd.connected) root.noxd.runAction({ lock: {} }); lifecycle.requestClose("action"); break;
            case "suspend": if (root.noxd && root.noxd.connected) root.noxd.runAction({ suspend: {} }); lifecycle.requestClose("action"); break;
            case "reboot": if (root.noxd && root.noxd.connected) root.noxd.runAction({ reboot: {} }); lifecycle.requestClose("action"); break;
            case "power_off": if (root.noxd && root.noxd.connected) root.noxd.runAction({ power_off: {} }); lifecycle.requestClose("action"); break;
            case "toggle_dnd": lifecycle.requestClose("action"); break;
            case "screenshot": lifecycle.requestClose("screenshot"); break;
            case "reload_shell": launchProcess.command = ["systemctl", "--user", "reload", "noxflow-shell"]; launchProcess.running = true; lifecycle.requestClose("action"); break;
            case "copy_to_clipboard": if (item.actionParams && item.actionParams.text) { var escaped = item.actionParams.text.replace(/'/g, "'\\''"); launchProcess.command = ["sh", "-c", "printf '%s' '" + escaped + "' | wl-copy"]; launchProcess.running = true; } lifecycle.requestClose("action"); break;
            case "calculator": lifecycle.requestClose("action"); break;
            default: if (root.noxd && root.noxd.connected) { var action = {}; action[item.action] = item.actionParams || {}; root.noxd.runAction(action); } lifecycle.requestClose("action"); break;
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
