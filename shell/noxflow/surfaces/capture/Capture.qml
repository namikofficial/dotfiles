// Capture — region selector + OCR/Lens/workflow overlay.
// Super+Shift+S to open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd

    signal fullScreenCaptureRequested(string destinationPath)

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    // Selection
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property bool selecting: false
    property bool hasSelection: false
    property real dragStartX: 0
    property real dragStartY: 0

    // Toolbar
    property bool showToolbar: false
    property bool showOcrResult: false
    property bool showWordOverlay: false
    property string ocrText: ""
    property string ocrLanguage: "eng"
    property var ocrWords: []
    property string analysisType: ""

    readonly property var settings: typeof shellRoot !== "undefined" && shellRoot.quickSnipSettings
        ? shellRoot.quickSnipSettings : null

    function initSettings() {
        if (typeof shellRoot !== "undefined" && shellRoot && shellRoot.quickSnipSettings)
            root.ocrLanguage = shellRoot.quickSnipSettings.ocrLanguage
    }
    Component.onCompleted: initSettings()

    anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
    // The normal bar reserves 40px, so explicitly pull this fullscreen
    // capture surface back over that band. Otherwise drag selection starts
    // below the topbar and y=0 can never be selected.
    margins.top: -Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    margins.bottom: 0
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            showToolbar = false; showOcrResult = false; showWordOverlay = false
            hasSelection = false; selecting = false
            selX = 0; selY = 0; selW = 0; selH = 0
            Qt.callLater(function() { focusRoot.forceActiveFocus(); })
        }
    }

    // ── Focus + nested Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
        Keys.onEscapePressed: root.handleEscape()
    }

    function handleEscape() {
        if (showOcrResult) { showOcrResult = false; showWordOverlay = true; return }
        if (showToolbar) { showToolbar = false; hasSelection = false; selecting = false; return }
        if (selecting) { selecting = false; return }
        lifecycle.requestClose("escape")
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, Theme.Tokens.glassScrimAlpha)

        Rectangle {
            x: root.selX; y: root.selY; width: root.selW; height: root.selH
            color: "transparent"; border.color: Theme.Tokens.tonalPrimary
            border.width: 2; radius: 4
            visible: root.hasSelection || root.selecting

            Rectangle {
                anchors.left: parent.left; anchors.top: parent.top
                anchors.margins: -3; width: 6; height: 6; radius: 3
                color: Theme.Tokens.tonalPrimary
            }
            Rectangle {
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: -3; width: 6; height: 6; radius: 3
                color: Theme.Tokens.tonalPrimary
            }
            Rectangle {
                anchors.left: parent.left; anchors.bottom: parent.bottom
                anchors.margins: -3; width: 6; height: 6; radius: 3
                color: Theme.Tokens.tonalPrimary
            }
            Rectangle {
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: -3; width: 6; height: 6; radius: 3
                color: Theme.Tokens.tonalPrimary
            }
            Text {
                anchors.bottom: parent.top; anchors.left: parent.left
                anchors.margins: 4
                text: Math.round(root.selW) + "×" + Math.round(root.selH)
                color: Theme.Tokens.textPrimary
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                style: Text.Outline; styleColor: "#000000"
            }
        }
    }

    // ── Mouse region selector ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor

        onPressed: function(mouse) {
            if (root.showToolbar || root.showOcrResult) return
            root.dragStartX = mouse.x; root.dragStartY = mouse.y
            root.selX = mouse.x; root.selY = mouse.y
            root.selW = 0; root.selH = 0
            root.selecting = true; root.hasSelection = false
        }
        onPositionChanged: function(mouse) {
            if (!root.selecting) return
            var x1 = Math.min(root.dragStartX, mouse.x)
            var y1 = Math.min(root.dragStartY, mouse.y)
            var x2 = Math.max(root.dragStartX, mouse.x)
            var y2 = Math.max(root.dragStartY, mouse.y)
            root.selX = x1; root.selY = y1
            root.selW = x2 - x1; root.selH = y2 - y1
        }
        onReleased: function(mouse) {
            if (!root.selecting) return
            root.selecting = false
            if (root.selW < 10 || root.selH < 10) {
                lifecycle.requestClose("tinySelection")
                return
            }
            root.hasSelection = true; root.showToolbar = true
        }
    }

    // ── Toolbar ──
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.Tokens.scaled(Theme.Tokens.spacingXxl)
        height: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
        implicitWidth: toolbarRow.width + Theme.Tokens.scaled(Theme.Tokens.spacingXl)
        radius: Theme.Tokens.radiusPill
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, Theme.Tokens.glassPanelAlpha)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        visible: root.showToolbar
        opacity: root.showToolbar ? 1 : 0
        scale: root.showToolbar ? 1 : 0.8

        RowLayout {
            id: toolbarRow
            anchors.centerIn: parent; spacing: Theme.Tokens.spacingSm
            Components.IconButton {
                iconText: "📋"; accessibleName: "Copy to clipboard"
                onClicked: root.performAction("copy")
            }
            Components.IconButton {
                iconText: "💾"; accessibleName: "Save screenshot"
                onClicked: root.performAction("save")
            }
            Components.IconButton {
                iconText: "🔤"; accessibleName: "OCR (text recognition)"
                onClicked: root.performOcr()
            }
            Components.IconButton {
                iconText: "R"; accessibleName: "Raw OCR layout"
                checked: root.settings ? root.settings.rawMode : false
                onClicked: { if (root.settings) root.settings.rawMode = !root.settings.rawMode }
            }
            Components.IconButton {
                iconText: "S"; accessibleName: "Single line"
                checked: root.settings ? root.settings.singleLine : false
                onClicked: { if (root.settings) root.settings.singleLine = !root.settings.singleLine }
            }
            Components.IconButton {
                iconText: "D"; accessibleName: "Direct mode (copy image)"
                checked: root.settings ? root.settings.directMode : false
                onClicked: {
                    if (root.settings) {
                        root.settings.directMode = !root.settings.directMode
                        if (root.settings.directMode) root.performAction("copy")
                    }
                }
            }
            Components.IconButton {
                iconText: "🌐"; accessibleName: "Translate via Lens"
                onClicked: root.performAction("lens")
            }
            Components.IconButton {
                iconText: "🔍"; accessibleName: "Search image"
                onClicked: root.performAction("search")
            }
            Components.IconButton {
                iconText: "✕"; accessibleName: "Close"
                onClicked: root.handleEscape()
            }
        }
    }

    // ── OCR result overlay ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.5, Theme.Tokens.scaled(500))
        height: Math.min(parent.height * 0.4, Theme.Tokens.scaled(300))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, Theme.Tokens.glassPanelAlpha)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        visible: root.showOcrResult
        opacity: root.showOcrResult ? 1 : 0

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "OCR Result"; color: Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true
                    Layout.fillWidth: true
                }
                Rectangle {
                    visible: root.analysisType !== ""
                    height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                    implicitWidth: analysisTypeLabel.width + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    radius: Theme.Tokens.radiusPill
                    color: Theme.Tokens.surfaceSurfaceVariant
                    Text {
                        id: analysisTypeLabel; anchors.centerIn: parent
                        text: root.analysisType.toUpperCase()
                        color: Theme.Tokens.tonalPrimary
                        font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true
                    }
                }
                Components.IconButton {
                    iconText: "📋"; accessibleName: "Copy OCR text"
                    onClicked: root.copyText(root.ocrText)
                }
                Components.IconButton {
                    iconText: "🔗"; accessibleName: "Open URL"
                    visible: root.analysisType === "url"
                    onClicked: root.openAnalyzedText()
                }
                Components.IconButton {
                    iconText: "🤖"; accessibleName: "Ask AI"
                    visible: root.analysisType === "ai"
                    onClicked: root.openAnalyzedText()
                }
                Components.IconButton {
                    iconText: "✕"; accessibleName: "Close OCR"
                    onClicked: root.handleEscape()
                }
            }

            RowLayout {
                Layout.fillWidth: true; visible: root.ocrWords.length > 0
                Components.Toggle {
                    checked: root.showWordOverlay
                    onToggled: root.showWordOverlay = !root.showWordOverlay
                }
                Text {
                    text: "Show word highlights (" + root.ocrWords.length + " words)"
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                }
            }

            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: ocrBody.height + Theme.Tokens.spacingMd; clip: true

                TextEdit {
                    id: ocrBody
                    width: parent ? parent.width : 0
                    text: root.ocrText || "No text detected."
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    wrapMode: Text.Wrap; readOnly: true; selectByMouse: true
                }
            }
        }
    }

    // ── Word overlay ──
    WordOverlay {
        id: wordOverlay
        visible: root.showWordOverlay && root.ocrWords.length > 0
        z: 10; words: root.ocrWords
        regionX: root.selX; regionY: root.selY; scaleFactor: 1.0
        onWordCopied: function(text) { root.copyText(text) }
        onWordSelected: function(index, text) { root.ocrText = text; root.showOcrResult = true }
    }

    // ── Actions ──
    function globalRegion() {
        var ox = root.screen && root.screen.x !== undefined ? Number(root.screen.x) : 0
        var oy = root.screen && root.screen.y !== undefined ? Number(root.screen.y) : 0
        return Math.round(ox + root.selX) + "," + Math.round(oy + root.selY) + " "
            + Math.round(root.selW) + "x" + Math.round(root.selH)
    }

    function performAction(action) {
        var region = root.globalRegion()

        switch (action) {
            case "copy":
                copyToClipboard.command = ["sh", "-c", "grim -g \"" + region + "\" - | wl-copy"]
                copyToClipboard.running = true; lifecycle.requestClose("copyDone")
                break
            case "save": {
                var base = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
                var file = base + "/Screenshots/" + new Date().toISOString().replace(/[:T]/g, "-").replace(/\..*$/, "") + ".png"
                saveScreenshot.command = ["sh", "-c",
                    "mkdir -p \"$(dirname '" + file.replace(/'/g, "'\\''") + "')\""
                    + " && grim -g \"" + region + "\" \"" + file + "\""
                    + " && notify-send 'Screenshot saved' \"" + file + "\" -t 3000"
                    + " || notify-send 'Screenshot failed' 'grim returned an error' -u critical"]
                saveScreenshot.running = true; lifecycle.requestClose("saveDone")
                break
            }
            case "lens":
                lensUploadFile = "/tmp/nox-capture-lens.png"
                lensCapture.command = ["sh", "-c", "grim -g \"" + region + "\" \"" + lensUploadFile + "\""]
                lensCapture.running = true
                break
            case "search":
                searchImageFile = "/tmp/nox-capture-search.png"
                searchCapture.command = ["sh", "-c", "grim -g \"" + region + "\" \"" + searchImageFile + "\""]
                searchCapture.running = true; lifecycle.requestClose("searchDone")
                break
        }
    }

    property string lensUploadFile: ""
    property string searchImageFile: ""

    property Process lensCapture: Process {
        running: false
        onExited: function(code, status) {
            if (code !== 0) return
            lensUpload.command = ["sh", "-c",
                "curl -s --data-binary @" + lensUploadFile
                + " \"https://lens.google.com/v3/upload\" > /tmp/nox-lens-result.html"
                + " && xdg-open /tmp/nox-lens-result.html"]
            lensUpload.running = true
        }
    }
    property Process lensUpload: Process { running: false }

    property Process searchCapture: Process {
        running: false
        onExited: function(code, status) {
            if (code !== 0) return
            openUrlProcess.command = ["xdg-open",
                "https://images.google.com/searchbyimage?image_url=file://" + searchImageFile]
            openUrlProcess.running = true
        }
    }
    property Process openUrlProcess: Process { running: false }

    property Process copyToClipboard: Process {
        id: copyToClipboard; running: false
        stdinEnabled: true
        onStarted: { copyToClipboard.write(root.ocrText); copyToClipboard.stdinEnabled = false }
    }
    property Process notifyProcess: Process { running: false }
    property Process saveScreenshot: Process { running: false }

    function copyText(text) {
        copyToClipboard.command = ["wl-copy"]; copyToClipboard.running = true
    }

    // ── OCR pipeline ──
    property string ocrBuffer: ""

    function performOcr() {
        var region = root.globalRegion()
        root.showToolbar = false; root.showOcrResult = true
        root.ocrText = "Recognizing text…"; root.ocrWords = []; root.analysisType = ""

        var w = Math.round(root.selW); var h = Math.round(root.selH)
        var area = w * h; var isSmall = area < 40000; var isTiny = h < 30
        var upscale = isTiny ? "-resize 400%" : isSmall ? "-resize 200%" : ""
        var psm = root.settings && root.settings.rawMode ? "6"
            : (isTiny || h < 50 || w / h > 10) ? "7" : "3"

        var postProcess = ""
        if (root.settings && root.settings.rawMode) {
            postProcess += " | sed 's/[[:space:]]*$//'"
        } else if (root.settings && root.settings.singleLine) {
            postProcess += " | awk 'BEGIN{RS=\"\"; ORS=\"\\n\\n\"} {$1=$1; print}'"
                + " | sed 's/[[:space:]]*$//' | tr '\\n' ' ' | sed 's/  */ /g; s/[[:space:]]*$//'"
        } else {
            postProcess += " | awk 'BEGIN{RS=\"\"; ORS=\"\\n\\n\"} {$1=$1; print}'"
                + " | sed 's/[[:space:]]*$//'"
        }

        ocrProcess.command = ["sh", "-c",
            "grim -g \"" + region + "\" -s 2 - | magick - " + upscale
            + " -colorspace Gray -depth 8 - | tesseract stdin stdout -l " + root.ocrLanguage
            + " --oem 1 --psm " + psm + " 2>/dev/null" + postProcess]
        ocrBuffer = ""; ocrProcess.running = true
    }

    property Process ocrProcess: Process {
        id: ocrProcess; running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.ocrBuffer += data }
        }
        onExited: function(code, status) {
            var text = root.ocrBuffer.trim()
            if (code !== 0 || text === "") {
                root.ocrText = "OCR failed. Is tesseract installed?"; return
            }
            root.ocrText = text; root.analysisType = root.analyzeText(text)
            var clean = text.replace(/\n/g, " ").replace(/\s+/g, " ").trim()
            var snippet = clean.substring(0, 100)
            if (clean.length > 100) snippet += "…"
            notifyProcess.command = ["sh", "-c",
                "notify-send 'OCR Copied' '" + snippet.replace(/'/g, "'\\''") + "' -t 3000"]
            notifyProcess.running = true
            var region2 = root.globalRegion()
            tsvProcess.command = ["sh", "-c",
                "grim -g \"" + region2 + "\" -s 2 - | tesseract stdin stdout -l "
                + root.ocrLanguage + " tsv 2>/dev/null"]
            tsvBuffer = ""; tsvProcess.running = true
        }
    }

    property string tsvBuffer: ""
    property Process tsvProcess: Process {
        id: tsvProcess; running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.tsvBuffer += data }
        }
        onExited: function(code, status) {
            if (code !== 0) return
            root.parseTsv(root.tsvBuffer)
        }
    }

    function parseTsv(tsv) {
        var lines = tsv.split("\n"); var words = []; var header = true
        var colLevel = -1, colX = -1, colY = -1, colW = -1, colH = -1, colText = -1, colConf = -1
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("\t")
            if (parts.length < 5) continue
            if (header) {
                for (var c = 0; c < parts.length; c++) {
                    if (parts[c] === "level") colLevel = c
                    else if (parts[c] === "left") colX = c
                    else if (parts[c] === "top") colY = c
                    else if (parts[c] === "width") colW = c
                    else if (parts[c] === "height") colH = c
                    else if (parts[c] === "text") colText = c
                    else if (parts[c] === "conf") colConf = c
                }
                header = false; continue
            }
            var level = parseInt(parts[colLevel])
            if (level !== 5) continue
            var conf = parseInt(parts[colConf])
            if (conf < 10) continue
            words.push({
                x: parseFloat(parts[colX]) || 0,
                y: parseFloat(parts[colY]) || 0,
                w: parseFloat(parts[colW]) || 0,
                h: parseFloat(parts[colH]) || 0,
                text: parts[colText] || "",
                confidence: conf,
                line: 0
            })
        }
        root.ocrWords = words
    }

    function analyzeText(text) {
        if (!text || text === "") return ""
        if (/^https?:\/\/[^\s]{4,}$/i.test(text.trim())) return "url"
        if (/^[a-z0-9]([a-z0-9-]*[a-z0-9])?\.[a-z]{2,}(\/\S*)?$/i.test(text.trim().split("\n")[0]))
            return "url"
        var codeCount = 0; var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (/^(function|const|let|var|if|for|while|import|export|def |class |int |String|public |private |=>)/.test(line))
                codeCount++
            if (/[{}().;]$/.test(line)) codeCount++
            if (/^[a-zA-Z_]\w*\s*\(/.test(line)) codeCount++
        }
        if (codeCount >= 3 || (codeCount >= 2 && lines.length >= 3)) return "code"
        if (lines.length === 1 && text.trim().split(/\s+/).length <= 2 && text.length < 60)
            return "dictionary"
        var wordCount = text.split(/\s+/).length
        var aiThreshold = (root.settings && root.settings.aiThreshold) || 15
        if (wordCount >= aiThreshold) return "ai"
        if (wordCount > 2) return "search"
        return ""
    }

    function openAnalyzedText() {
        if (root.analysisType === "url") {
            var url = root.ocrText.trim()
            if (!url.startsWith("http")) url = "https://" + url
            Quickshell.exec("xdg-open \"" + url + "\"")
        } else if (root.analysisType === "ai") {
            if (root.noxd && root.noxd.connected)
                root.noxd.runAction({ ai_query: { text: root.ocrText } })
        }
    }

    function fullScreenSave() {
        var base = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
        var file = base + "/Screenshots/" + new Date().toISOString().replace(/[:T]/g, "-").replace(/\..*$/, "") + ".png"
        root.fullScreenCaptureRequested(file)
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close"); }
}
