// Universal Launcher — fuzzy-search application/window/command overlay.
// Stolen from: DankMaterialShell + Caelestia.
// Super+Space to open. Modes: Apps, Windows, Commands, Calculator.

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
    property var clipboardModel: null  // ClipboardModel, wired from shell.qml

    // ── Modes ──
    readonly property var modes: ["Apps", "Windows", "Commands", "Calc", "Ask AI", "Clipboard"]
    property int activeMode: 0
    property string searchText: ""
    property var filteredResults: []
    property int selectedIndex: 0
    property bool launcherOpen: false

    // ── Shared Process for launcher actions ──
    property Process launchProcess: Process {
        command: []
        running: false
    }

    // ── AI mode state ──
    property string aiQuery: ""
    property string aiResponse: ""
    property bool aiLoading: false
    property int aiStatus: 0 // 0=idle, 1=loading, 2=done, 3=error
    // Configurable via `noxctl`-adjacent env or noxd setting; defaults to local llama-swap.
    readonly property string aiEndpoint: Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/v1/chat/completions"
    readonly property string aiModel: Quickshell.env("NOXFLOW_AI_MODEL") || "qwen3-4b-local"

    // ── Window setup (full-screen overlay) ──
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: launcherOpen

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.6)
        opacity: root.launcherOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(200) } }

        TapHandler { onTapped: root.close() }
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
        scale: root.launcherOpen ? 1 : 0.85
        opacity: root.launcherOpen ? 1 : 0

        Behavior on scale { NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(150) } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // ── Search field ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingMd

                Components.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    label: ""
                    showClearButton: true
                    focus: true
                    placeholderText: root.activeMode === 4 ? "Ask anything..." : "Search apps, windows, commands..."
                    onTextChanged: {
                        root.searchText = text;
                        if (root.activeMode === 4) {
                            root.aiQuery = text;
                            root.triggerAiQuery();
                        }
                        root.filterResults();
                    }
                    Keys.onDownPressed: root.navigateList(1)
                    Keys.onUpPressed: root.navigateList(-1)
                    Keys.onReturnPressed: root.activateSelected()
                    Keys.onEscapePressed: root.close()
                    Keys.onTabPressed: function(event) {
                        root.activeMode = (root.activeMode + 1) % root.modes.length;
                        root.resetAi();
                        root.filterResults();
                        event.accepted = true;
                    }
                }

                // Results count badge
                Rectangle {
                    visible: root.filteredResults.length > 0
                    height: Theme.Tokens.scaled(20)
                    implicitWidth: countText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingSm)
                    radius: Theme.Tokens.radiusPill
                    color: Theme.Tokens.tonalPrimaryContainer
                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: root.filteredResults.length + " results"
                        color: Theme.Tokens.tonalOnPrimaryContainer
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.bold: true
                    }
                }
            }

            // ── Mode tabs ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingXs
                Repeater {
                    model: root.modes
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                        radius: Theme.Tokens.radiusPill
                        color: root.activeMode === index ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: root.activeMode === index ? Theme.Tokens.tonalPrimary : "transparent"
                        border.width: root.activeMode === index ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: modelData + (index === 0 && root.noxd && root.noxd.connected ? "" : "")
                            color: root.activeMode === index ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelMedium
                            font.family: Theme.Tokens.typographyFontFamily
                        }
                        TapHandler {
                            onTapped: {
                                root.activeMode = index;
                                root.filterResults();
                                searchField.forceActiveFocus();
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Results list ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // AI response panel (shown in AI mode when there's a result)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusMd
                    color: Theme.Tokens.surfaceSurfaceContainer
                    visible: root.activeMode === 4 && (root.aiStatus > 0 || root.aiLoading)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingMd
                        spacing: Theme.Tokens.spacingSm

                        // Loading indicator
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.aiLoading
                            spacing: Theme.Tokens.spacingSm
                            Components.LoadingIndicator {}
                            Text {
                                text: "Thinking..."
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                                font.family: Theme.Tokens.typographyFontFamily
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.aiQuery
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                                elide: Text.ElideRight
                                Layout.maximumWidth: Theme.Tokens.scaled(200)
                            }
                        }

                        // AI response text
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: aiText.height
                            visible: !root.aiLoading && root.aiResponse !== ""

                            Text {
                                id: aiText
                                width: parent.width
                                text: root.aiResponse
                                color: root.aiStatus === 3 ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium
                                font.family: Theme.Tokens.typographyFontFamily
                                wrapMode: Text.WordWrap
                                textFormat: Text.RichText
                                onLinkActivated: function(link) { Qt.openUrlExternally(link); }
                            }
                        }
                    }
                }

                // Normal result list (hidden in AI mode when we have a response)
                Text {
                    anchors.centerIn: parent
                    text: root.searchText === "" ? "Type to search..." : "No results"
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: root.filteredResults.length === 0 && !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))
                }

                ListView {
                    id: resultsList
                    anchors.fill: parent
                    model: root.filteredResults
                    currentIndex: root.selectedIndex
                    spacing: Theme.Tokens.spacingXs
                    visible: !(root.activeMode === 4 && (root.aiResponse !== "" || root.aiLoading))

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: Theme.Tokens.scaled(Theme.Tokens.heightControl)
                        radius: Theme.Tokens.radiusSm
                        color: index === root.selectedIndex ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                        border.color: index === root.selectedIndex ? Theme.Tokens.tonalPrimary : "transparent"
                        border.width: index === root.selectedIndex ? 1 : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.Tokens.spacingSm
                            spacing: Theme.Tokens.spacingMd

                            Text {
                                text: modelData.icon || "◆"
                                color: index === root.selectedIndex ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.tonalPrimary
                                font.pixelSize: Theme.Tokens.iconMd
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: modelData.title || modelData.name || "Unknown"
                                    color: index === root.selectedIndex ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textPrimary
                                    font.family: Theme.Tokens.typographyFontFamily
                                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.subtitle || modelData.description || modelData.comment || ""
                                    color: index === root.selectedIndex ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                }
                            }

                            Text {
                                text: modelData.shortcut || ""
                                color: index === root.selectedIndex ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                visible: text !== ""
                            }
                        }

                        TapHandler {
                            onTapped: {
                                root.selectedIndex = index;
                                root.activateSelected();
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
    }

    // ── AI HTTP client (XMLHttpRequest via QML JS engine) ──
    property var aiXhr: null
    property string pendingAiQuery: ""

    property Timer aiTimer: Timer {
        id: aiTimer
        repeat: false
        interval: 400
        onTriggered: root.executeAiQuery(root.pendingAiQuery)
    }

    function triggerAiQuery() {
        var query = searchText.trim();
        if (query.length < 3) {
            if (aiStatus !== 0) resetAi();
            return;
        }

        // Debounce: cancel previous request
        if (aiXhr) { aiXhr.abort(); aiXhr = null; }
        pendingAiQuery = query;
        aiTimer.restart();
    }

    function executeAiQuery(query) {
        aiLoading = true;
        aiStatus = 1;
        aiResponse = "";

        var xhr = new XMLHttpRequest();
        aiXhr = xhr;
        xhr.open("POST", aiEndpoint, true);
        xhr.setRequestHeader("Content-Type", "application/json");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            aiXhr = null;
            aiLoading = false;

            if (xhr.status === 200) {
                try {
                    var json = JSON.parse(xhr.responseText);
                    var text = json.choices && json.choices.length > 0
                        ? json.choices[0].message.content
                        : "No response";
                    aiResponse = text;
                    aiStatus = 2; // done
                } catch (e) {
                    aiResponse = "Failed to parse AI response";
                    aiStatus = 3; // error
                }
            } else {
                aiResponse = "AI request failed (HTTP " + xhr.status + ")";
                aiStatus = 3;
            }
        };

        var body = JSON.stringify({
            model: aiModel,
            messages: [
                { role: "system", content: "You are a helpful assistant. Answer concisely and accurately." },
                { role: "user", content: query }
            ],
            temperature: 0.7,
            max_tokens: 512,
            stream: false
        });
        xhr.send(body);
    }

    function resetAi() {
        aiQuery = "";
        aiResponse = "";
        aiLoading = false;
        aiStatus = 0;
        if (aiXhr) { aiXhr.abort(); aiXhr = null; }
    }

    // ── Result sources ──
    property var appCache: []
    property var windowCache: []
    property bool scanStarted: false

    // ── Desktop file scanner ──
    property string desktopBuffer: ""
    property Process desktopScanner: Process {
        id: desktopScanner
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.desktopBuffer += data; }
        }
        onExited: function(code, status) {
            if (root.desktopBuffer) {
                root.parseDesktopFiles(root.desktopBuffer);
                root.desktopBuffer = "";
                root.filterResults(); // refresh results after scan
            }
        }
    }

    function scanDesktopFiles() {
        if (scanStarted) return; // only scan once
        scanStarted = true;
        // Simpler approach: just find and parse with grep+awk via a helper script
        desktopScanner.command = ["sh", "-c",
            "find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | " +
            "head -200 | while read f; do " +
            "  name=$(grep -m1 '^Name=' \"$f\" 2>/dev/null | cut -d= -f2-); " +
            "  exec=$(grep -m1 '^Exec=' \"$f\" 2>/dev/null | cut -d= -f2- | sed 's/ .*//' | sed 's/%[a-zA-Z]//g'); " +
            "  icon=$(grep -m1 '^Icon=' \"$f\" 2>/dev/null | cut -d= -f2-); " +
            "  [ -n \"$name\" ] && [ -n \"$exec\" ] && echo \"$name|$exec|$icon\"; " +
            "done | sort -u"
        ];
        desktopScanner.running = true;
    }

    function parseDesktopFiles(data) {
        if (!data) return;
        var lines = data.trim().split("\n");
        var apps = [];
        var iconMap = {
            "firefox": "🦊", "firefox-esr": "🦊", "librewolf": "🦊",
            "kitty": "⚡", "alacritty": "⚡", "wezterm": "⚡", "foot": "⚡",
            "thunar": "📁", "nautilus": "📁", "dolphin": "📁", "pcmanfm": "📁",
            "code": "💻", "codium": "💻", "code-oss": "💻",
            "obsidian": "📝", "logseq": "📝",
            "discord": "💬", "vesktop": "💬", "telegram": "💬", "element": "💬",
            "spotify": "🎵", "ncmpcpp": "🎵", "mpd": "🎵",
            "gimp": "🎨", "inkscape": "🎨", "krita": "🎨",
            "blender": "🔄", "godot": "🎮",
            "libreoffice": "📄", "onlyoffice": "📄",
            "evince": "📖", "zathura": "📖", "okular": "📖",
            "keepassxc": "🔑", "bitwarden": "🔑",
            "virt-manager": "🖥️", "gnome-boxes": "🖥️",
            "steam": "🎮", "lutris": "🎮", "heroic": "🎮",
            "gparted": "💽", "gnome-disks": "💽",
        };
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|");
            if (parts.length < 2) continue;
            var title = parts[0].trim();
            var cmd = parts[1].trim();
            var iconName = parts.length > 2 ? parts[2].trim().toLowerCase() : "";
            // Extract basename for icon lookup (full paths like /usr/lib/firefox/firefox → firefox)
            var basename = cmd.split("/").pop().split(" ")[0].toLowerCase();
            var icon = iconMap[basename] || iconMap[cmd] || iconMap[iconName] || "◆";
            if (!title || !cmd) continue;
            apps.push({
                title: title,
                icon: icon,
                subtitle: cmd,
                action: "launch",
                actionParams: { command: cmd }
            });
        }
        appCache = sortApps(apps.length > 0 ? apps : buildDefaultApps());
    }

    function buildDefaultApps() {
        return [
            { title: "Firefox", icon: "🦊", subtitle: "Web browser", action: "launch", actionParams: { command: "firefox" } },
            { title: "Kitty", icon: "⚡", subtitle: "Terminal emulator", action: "launch", actionParams: { command: "kitty" } },
            { title: "Thunar", icon: "📁", subtitle: "File manager", action: "launch", actionParams: { command: "thunar" } },
            { title: "Code", icon: "💻", subtitle: "Visual Studio Code", action: "launch", actionParams: { command: "code" } },
            { title: "Settings", icon: "☰", subtitle: "System settings", action: "launch", actionParams: { command: "gnome-controlcenter" } },
            { title: "Obsidian", icon: "📝", subtitle: "Notes", action: "launch", actionParams: { command: "obsidian" } },
        ];
    }

    // ── Filtering ──
    function filterResults() {
        // Trigger desktop file scan on first filter — use a separate flag so defaults don't block it
        if (activeMode === 0 && !root.scanStarted) {
            appCache = buildDefaultApps();
            scanDesktopFiles();
        }
        var query = searchText.toLowerCase().trim();
        selectedIndex = 0;

        if (activeMode === 4) {
            // AI mode — no list results, uses AI panel
            filteredResults = [];
            return;
        }

        if (activeMode === 5) {
            // Clipboard mode
            if (!root.clipboardModel) { filteredResults = []; return; }
            var clipItems = root.clipboardModel.asLauncherItems(20);
            if (query === "") { filteredResults = clipItems; return; }
            filteredResults = clipItems.filter(function(item) {
                return item.title.toLowerCase().indexOf(query) >= 0;
            });
            return;
        }

        if (activeMode === 3) {
            // Calculator mode
            if (query === "") { filteredResults = []; return; }
            filteredResults = [{ title: "= " + evaluateCalc(query), icon: "∑", subtitle: query }];
            return;
        }

        var source = [];
        if (activeMode === 0) source = buildAppResults();
        else if (activeMode === 1) source = buildWindowResults();
        else if (activeMode === 2) source = buildCommandResults();

        if (query === "") {
            filteredResults = source.slice(0, 20);
            return;
        }

        // Simple fuzzy filter
        var results = [];
        for (var i = 0; i < source.length; i++) {
            var item = source[i];
            var haystack = ((item.title || "") + " " + (item.subtitle || "") + " " + (item.description || "")).toLowerCase();
            if (haystack.indexOf(query) >= 0) {
                results.push(item);
                if (results.length >= 30) break;
            }
        }
        filteredResults = results;
    }

    function buildAppResults() {
        if (appCache.length > 0) return appCache;
        // Fallback if scan hasn't finished
        return buildDefaultApps();
    }

    function sortApps(apps) {
        // Future: sort by frequency
        return apps;
    }

    function buildWindowResults() {
        if (!hyprland || !hyprland.windows) return [];

        return hyprland.windows.map(function(w) {
            return {
                title: w.title || "Untitled",
                icon: "▭",
                subtitle: w.workspace ? "ws " + (w.workspace.name || w.workspace.id || "") : "",
                action: "focus_window",
                actionParams: { address: w.address || "" }
            };
        });
    }

    function buildCommandResults() {
        return [
            { title: "Lock", icon: "🔒", subtitle: "Lock the screen", action: "lock", actionParams: {} },
            { title: "Suspend", icon: "⏾", subtitle: "Suspend to RAM", action: "suspend", actionParams: {} },
            { title: "Reboot", icon: "↻", subtitle: "Reboot the system", action: "reboot", actionParams: {} },
            { title: "Power Off", icon: "⏻", subtitle: "Shut down", action: "power_off", actionParams: {} },
            { title: "Toggle DND", icon: "⊘", subtitle: "Do not disturb", action: "toggle_dnd", actionParams: {} },
            { title: "Screenshot", icon: "◉", subtitle: "Take a screenshot", action: "screenshot", actionParams: {} },
            { title: "Reload shell", icon: "↻", subtitle: "Reload NoxFlow shell", action: "reload_shell", actionParams: {} },
        ];
    }

    // ── Calculator ──
    function evaluateCalc(expr) {
        try {
            // Safe arithmetic via Function constructor (QML eval alternative)
            var sanitized = expr.replace(/[^0-9+\-*/.()% ]/g, "");
            var result = new Function("return (" + sanitized + ")")();
            if (typeof result === "number" && isFinite(result)) return String(Math.round(result * 100) / 100);
            return "?";
        } catch (e) {
            return "?";
        }
    }

    // ── Navigation ──
    function navigateList(delta) {
        if (filteredResults.length === 0) return;
        selectedIndex = (selectedIndex + delta + filteredResults.length) % filteredResults.length;
        resultsList.currentIndex = selectedIndex;
    }

    function activateSelected() {
        if (selectedIndex < 0 || selectedIndex >= filteredResults.length) return;
        var item = filteredResults[selectedIndex];
        if (!item || !item.action) return;

        switch (item.action) {
            case "launch":
                if (item.actionParams && item.actionParams.command) {
                    launchProcess.command = ["sh", "-c", item.actionParams.command];
                    launchProcess.running = true;
                }
                root.close();
                break;
            case "focus_window":
                if (root.noxd && root.noxd.connected && item.actionParams && item.actionParams.address) {
                    root.noxd.runAction({ window_focus: { address: item.actionParams.address } });
                }
                root.close();
                break;
            case "lock":
                if (root.noxd && root.noxd.connected) root.noxd.runAction({ lock: {} });
                root.close();
                break;
            case "suspend":
                if (root.noxd && root.noxd.connected) root.noxd.runAction({ suspend: {} });
                root.close();
                break;
            case "reboot":
                if (root.noxd && root.noxd.connected) root.noxd.runAction({ reboot: {} });
                root.close();
                break;
            case "power_off":
                if (root.noxd && root.noxd.connected) root.noxd.runAction({ power_off: {} });
                root.close();
                break;
            case "toggle_dnd":
                // Will wire to notification model
                root.close();
                break;
            case "screenshot":
                launchProcess.command = ["grim"];
                launchProcess.running = true;
                root.close();
                break;
            case "reload_shell":
                launchProcess.command = ["systemctl", "--user", "reload", "noxflow-shell"];
                launchProcess.running = true;
                root.close();
                break;
            case "copy_to_clipboard":
                if (item.actionParams && item.actionParams.text) {
                    var escaped = item.actionParams.text.replace(/'/g, "'\\''");
                    launchProcess.command = ["sh", "-c", "printf '%s' '" + escaped + "' | wl-copy"];
                    launchProcess.running = true;
                }
                root.close();
                break;
            case "calculator":
                root.close();
                break;
            default:
                if (root.noxd && root.noxd.connected) {
                    var action = {};
                    action[item.action] = item.actionParams || {};
                    root.noxd.runAction(action);
                }
                root.close();
                break;
        }
    }

    // ── Public API ──
    function open() {
        resetAi();
        launcherOpen = true;
        searchText = "";
        searchField.text = "";
        activeMode = 0;
        filteredResults = [];
        selectedIndex = 0;
        searchField.forceActiveFocus();
        filterResults();
    }

    function close() {
        resetAi();
        launcherOpen = false;
    }

    function toggle() {
        if (launcherOpen) close(); else open();
    }
}
