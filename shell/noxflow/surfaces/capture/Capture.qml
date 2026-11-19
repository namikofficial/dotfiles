// Capture — region selector + OCR/Lens/workflow overlay.
// Super+Shift+S to open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme" as Theme
import "../../config" as Config
import "../../components" as Components
import "OcrText.js" as OcrText

PanelWindow {
    id: root

    required property var noxd
    // Shared AI client owned by shell.qml. Capture analysis and the launcher's
    // "Ask AI" mode use the same endpoint, read from noxd settings.
    property var aiClient: null

    signal fullScreenCaptureRequested(string destinationPath)

    property bool captureHidden: false
    property var pendingCapture: null

    // Clear the complete layer before grim reads the compositor. Keep the
    // window mapped so Hyprland cannot fade a cached toolbar into the capture.
    Timer {
        id: captureDelay
        interval: 100
        onTriggered: {
            var action = root.pendingCapture
            root.pendingCapture = null
            if (action && lifecycle.active) action()
        }
    }

    function captureWithoutOverlay(action) {
        if (captureHidden || !lifecycle.active) return
        pendingCapture = action
        captureHidden = true
        captureDelay.start()
    }

    function completeCapture(success) {
        if (success) lifecycle.requestClose("captureDone")
        else captureHidden = false
    }

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
    exclusiveZone: 0; aboveWindows: true; color: "transparent"
    visible: lifecycle.active
    contentItem.visible: !root.captureHidden
    // Request the keyboard seat on open rather than on click; see the long
    // explanation in core/MorphSurface.qml.
    WlrLayershell.keyboardFocus: lifecycle.active && !root.captureHidden
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None
    WlrLayershell.namespace: "noxflow-capture"

    Connections {
        target: lifecycle
        function onClosed() {
            captureDelay.stop()
            root.pendingCapture = null
            root.captureHidden = false
        }
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

    // Keep the desktop at its original brightness while selecting.
    Item {
        anchors.fill: parent

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

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingLg)
        implicitWidth: selectionHint.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingXl)
        height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
        radius: Theme.Tokens.radiusPill
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineSubtle
        border.width: 1
        visible: lifecycle.active && !root.hasSelection && !root.selecting
        opacity: lifecycle.openProgress
        Accessible.name: "Drag to select a region. Escape cancels capture."

        Text {
            id: selectionHint
            anchors.centerIn: parent
            text: "Drag to select a region  ·  Esc to cancel"
            color: Theme.Tokens.textPrimary
            font.family: Theme.Tokens.typographyFontFamily
            font.pixelSize: Theme.Tokens.typographyLabelMedium
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
        color: Theme.Tokens.surfaceSurfaceContainerHighest
        border.color: Theme.Tokens.outlineDefault; border.width: 1
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
                iconText: "✎"; accessibleName: "Annotate screenshot"
                enabled: Config.Apps.isAvailable("satty")
                onClicked: root.performAction("annotate")
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
                    font.family: Theme.Tokens.typographyDisplayFamily
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
                    accessibleName: "Show word highlights"
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
        root.captureWithoutOverlay(function() { root.executeAction(action) })
    }

    function executeAction(action) {
        var region = root.globalRegion()
        var ts = new Date().toISOString().replace(/[:T]/g, "-").replace(/\..*$/, "")
            + "-" + Math.floor(Math.random() * 1000000)

        switch (action) {
            case "copy":
                copyToClipboard.run(["bash", "-o", "pipefail", "-c",
                    "grim -g \"" + region + "\" - | wl-copy"])
                break
            case "save": {
                var base = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
                var file = base + "/Screenshots/" + ts + ".png"
                saveScreenshot.runShell(
                    "mkdir -p \"$(dirname '" + file.replace(/'/g, "'\\''") + "')\""
                    + " && grim -g \"" + region + "\" \"" + file + "\""
                    + " && notify-send 'Screenshot saved' \"" + file + "\" -t 3000"
                    // No notify-send fallback here: saveScreenshot.onExited now
                    // reports the real exit code through notifyProcess, which is
                    // what the plan asked for instead of self-reporting in-shell.
                    + " || exit 1")
                break
            }
            case "annotate": {
                var base = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
                annotationInputFile = "/tmp/nox-capture-annotation-" + ts + ".png"
                annotationOutputFile = base + "/Screenshots/Annotated-" + ts + ".png"
                annotationCommand.runShell(
                    "mkdir -p " + root.shellQuote(base + "/Screenshots")
                    + " && grim -g " + root.shellQuote(region) + " " + root.shellQuote(annotationInputFile)
                    + " && satty --filename " + root.shellQuote(annotationInputFile)
                    + " --output-filename " + root.shellQuote(annotationOutputFile))
                break
            }
            case "lens": {
                lensUploadFile = "/tmp/nox-capture-lens-" + ts + ".png"
                lensResultFile = "/tmp/nox-lens-result-" + ts + ".html"
                lensCapture.runShell("grim -g \"" + region + "\" \"" + lensUploadFile + "\"")
                break
            }
            case "search": {
                searchImageFile = "/tmp/nox-capture-search-" + ts + ".png"
                searchResultFile = "/tmp/nox-search-result-" + ts + ".html"
                searchCapture.runShell("grim -g \"" + region + "\" \"" + searchImageFile + "\"")
                break
            }
        }
    }

    property string lensUploadFile: ""
    property string lensResultFile: ""
    property string searchImageFile: ""
    property string searchResultFile: ""
    property string annotationInputFile: ""
    property string annotationOutputFile: ""

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    property Components.Command annotationCommand: Components.Command {
        label: "Screenshot annotation"
        onExited: function(code) {
            if (code !== 0) {
                root.annotationCleanup.run(["rm", "-f", root.annotationInputFile])
                root.notifyProcess.run(["notify-send", "Annotation failed",
                    root.annotationCommand.failureText(), "-u", "critical"])
                root.lifecycle.requestClose("annotationFailed")
                return
            }
            root.annotationFinalize.runShell(
                "if [ -s " + root.shellQuote(root.annotationOutputFile) + " ]; then printf saved; fi"
                + "; rm -f " + root.shellQuote(root.annotationInputFile))
        }
    }
    property Components.Command annotationFinalize: Components.Command {
        label: "Finish screenshot annotation"
        onExited: function(code) {
            if (code !== 0) {
                root.notifyProcess.run(["notify-send", "Annotation cleanup failed",
                    root.annotationFinalize.failureText(), "-u", "critical"])
                root.lifecycle.requestClose("annotationFinalizeFailed")
            } else if (root.annotationFinalize.output.trim() === "saved") {
                root.annotationCopy.runShell("wl-copy < " + root.shellQuote(root.annotationOutputFile))
            } else {
                root.lifecycle.requestClose("annotationCancelled")
            }
        }
    }
    property Components.Command annotationCopy: Components.Command {
        label: "Copy annotated screenshot"
        onExited: function(code) {
            if (code !== 0) {
                root.notifyProcess.run(["notify-send", "Screenshot saved, copy failed",
                    root.annotationCopy.failureText(), "-u", "critical"])
            } else {
                root.notifyProcess.run(["notify-send", "Annotated screenshot saved",
                    root.annotationOutputFile, "-t", "3000"])
            }
            root.lifecycle.requestClose("annotationDone")
        }
    }
    property Components.Command annotationCleanup: Components.Command {
        label: "Clean up screenshot annotation"
    }

    property Components.Command lensCapture: Components.Command {
        label: "Screen capture"
        onExited: function(code) {
            root.completeCapture(false)
            if (code !== 0) {
                notifyProcess.run(["notify-send", "Lens capture failed", root.lensCapture.failureText(), "-u", "critical"])
                return
            }
            // Show disclosure that we're opening an external service
            notifyProcess.run(["notify-send", "Opening Google Lens", "Uploading image to lens.google.com", "-t", "3000"])
            lensUpload.runShell(
                "curl -s --data-binary @" + lensUploadFile
                + " \"https://lens.google.com/v3/upload\" > \"" + lensResultFile + "\""
                + " && xdg-open \"" + lensResultFile + "\""
                + " ; rc=$?; rm -f \"" + lensUploadFile + "\"; exit $rc")
        }
    }
    property Components.Command lensUpload: Components.Command {
        label: "Google Lens upload"
        onExited: function(code) {
            if (code !== 0) {
                notifyProcess.run(["notify-send", "Lens upload failed", root.lensUpload.failureText(), "-u", "critical"])
            }
            lifecycle.requestClose("lensDone")
        }
    }

    property Components.Command searchCapture: Components.Command {
        label: "Screen capture"
        onExited: function(code) {
            root.completeCapture(false)
            if (code !== 0) {
                notifyProcess.run(["notify-send", "Search capture failed", root.searchCapture.failureText(), "-u", "critical"])
                return
            }
            // Show disclosure before uploading to an external image-search service.
            notifyProcess.run(["notify-send", "Searching image", "Uploading image to Google", "-t", "3000"])
            searchUpload.runShell(
                "curl -s -L -F \"encoded_image=@" + searchImageFile + "\""
                + " -F \"image_content=\" \"https://www.google.com/searchbyimage/upload\""
                + " -o \"" + searchResultFile + "\""
                + " && xdg-open \"" + searchResultFile + "\""
                + " ; rc=$?; rm -f \"" + searchImageFile + "\"; exit $rc")
        }
    }
    property Components.Command searchUpload: Components.Command {
        label: "Image search upload"
        onExited: function(code) {
            if (code !== 0) {
                notifyProcess.run(["notify-send", "Image search failed", root.searchUpload.failureText(), "-u", "critical"])
            }
            lifecycle.requestClose("searchDone")
        }
    }
    property Components.Command openUrlProcess: Components.Command { label: "Open URL" }

    property Components.Command copyToClipboard: Components.Command {
        label: "Copy image"
        stdinEnabled: false
        onExited: function(code) {
            root.completeCapture(code === 0)
            if (code !== 0) {
                root.showCopyFailure(root.copyToClipboard)
            } else {
                root.showCopySuccess()
                lifecycle.requestClose("copyDone")
            }
        }
    }
    property Components.Command notifyProcess: Components.Command { label: "Desktop notification" }
    property Components.Command saveScreenshot: Components.Command {
        label: "Save screenshot"
        onExited: function(code) {
            root.completeCapture(code === 0)
            if (code !== 0) {
                // Report through the same notification path as every other
                // failure here, naming the real exit code.
                notifyProcess.run(["notify-send", "Save failed", root.saveScreenshot.failureText(), "-u", "critical"])
            } else {
                lifecycle.requestClose("saveDone")
            }
        }
    }
    property Components.Command textCopyProcess: Components.Command {
        label: "Copy text"
        stdinEnabled: true
        onExited: function(code) {
            if (code !== 0) {
                root.showCopyFailure(root.textCopyProcess)
            } else {
                root.showCopySuccess()
                lifecycle.requestClose("textCopyDone")
            }
        }
    }

    property bool copyFailureVisible: false
    property bool copySuccessVisible: false
    function showCopyFailure(failed) {
        copyFailureVisible = true
        notifyProcess.run(["notify-send", "Copy failed",
            failed ? failed.failureText() : "Copy failed", "-u", "critical"])
        Qt.callLater(function() { copyFailureVisible = false })
    }
    function showCopySuccess() {
        copySuccessVisible = true
        Qt.callLater(function() { copySuccessVisible = false })
    }

    function copyText(text) {
        if (!text || text === "" || text === "Recognizing text…" || text === "OCR failed. Is tesseract installed?") return
        textCopyProcess.stdinEnabled = true
        textCopyProcess.run(["wl-copy"])
        Qt.callLater(function() {
            if (textCopyProcess.running) {
                textCopyProcess.process.write(text)
                textCopyProcess.stdinEnabled = false
            }
        })
    }

    // ── OCR pipeline ──
    property string ocrCaptureFile: ""
    property string ocrPageSegmentationMode: "3"
    property bool ocrBusy: false

    function performOcr() {
        if (ocrBusy || captureHidden || !lifecycle.active) return
        if (!OcrText.validLanguage(ocrLanguage)) {
            showToolbar = false
            showOcrResult = true
            ocrText = "OCR language setting is invalid"
            return
        }
        ocrBusy = true
        root.captureWithoutOverlay(function() { root.executeOcr() })
    }

    function executeOcr() {
        var region = root.globalRegion()
        root.showToolbar = false; root.showOcrResult = true
        root.ocrText = "Recognizing text…"; root.ocrWords = []; root.analysisType = ""

        // Fail loudly and specifically when a required binary is absent,
        // instead of running a pipeline that dies on its first command.
        if (!Config.Apps.isAvailable("grim")) { root.ocrText = "Cannot capture: grim is not installed"; root.ocrBusy = false; root.completeCapture(false); return }
        if (!Config.Apps.isAvailable("tesseract")) { root.ocrText = "OCR unavailable: tesseract is not installed"; root.ocrBusy = false; root.completeCapture(false); return }

        var w = Math.round(root.selW); var h = Math.round(root.selH)
        ocrPageSegmentationMode = root.settings && root.settings.rawMode ? "6"
            : (h < 30 || w / h > 10) ? "7" : "3"

        // Capture once to a temp file, then derive both the OCR text and the
        // TSV word boxes from it. No second grim capture.
        var ts = String(Date.now())
        ocrCaptureFile = "/tmp/nox-ocr-" + ts + ".png"

        ocrCaptureProcess.run(["grim", "-g", region, ocrCaptureFile])
    }

    property Components.Command ocrCaptureProcess: Components.Command {
        label: "Capture OCR region"
        onExited: function(code) {
            if (code !== 0) {
                root.ocrText = "Capture failed: " + root.ocrCaptureProcess.failureText()
                root.ocrBusy = false
                root.completeCapture(false)
                root.cleanupOcrCapture()
                return
            }
            if (!root.ocrProcess.run(["tesseract", root.ocrCaptureFile, "stdout",
                "-l", OcrText.validLanguage(root.ocrLanguage), "--oem", "1",
                "--psm", root.ocrPageSegmentationMode])) {
                root.ocrText = "OCR could not start"
                root.ocrBusy = false
                root.completeCapture(false)
                root.cleanupOcrCapture()
            }
        }
    }

    property Components.Command ocrProcess: Components.Command {
        label: "OCR"
        onExited: function(code) {
            root.completeCapture(false)
            var text = OcrText.normalize(root.ocrProcess.output,
                root.settings && root.settings.rawMode,
                root.settings && root.settings.singleLine)
            if (code !== 0 || text === "") {
                root.ocrText = code !== 0
                    ? "OCR failed: " + root.ocrProcess.failureText()
                    : "No text recognised in the selection"
                root.ocrBusy = false
                root.cleanupOcrCapture()
                return
            }
            root.ocrText = text; root.analysisType = root.analyzeText(text)
            notifyProcess.run(["notify-send", "OCR ready", "Select the result to copy it", "-t", "3000"])
            // Use the same captured file for TSV word boxes - no second grim capture
            if (!tsvProcess.run(["tesseract", root.ocrCaptureFile, "stdout", "-l",
                OcrText.validLanguage(root.ocrLanguage), "tsv"])) {
                root.ocrBusy = false
                root.cleanupOcrCapture()
            }
        }
    }

    property Components.Command tsvProcess: Components.Command {
        label: "OCR word boxes"
        onExited: function(code) {
            if (code === 0) root.parseTsv(root.tsvProcess.output)
            root.ocrBusy = false
            root.cleanupOcrCapture()
        }
    }

    property Components.Command ocrCleanup: Components.Command { label: "OCR cleanup" }

    function cleanupOcrCapture() {
        if (!ocrCaptureFile) return
        ocrCleanup.run(["rm", "-f", ocrCaptureFile])
        ocrCaptureFile = ""
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
            Config.Apps.invoke("xdgOpen", [url])
        } else if (root.analysisType === "ai") {
            // Shared AI client — noxd has no `ai_query` action and rejects it
            // with invalid_request (probed).
            if (root.aiClient) root.aiClient.ask(root.ocrText, "Explain or summarise the following text concisely.")
            else console.warn("capture: AI analysis requested but no AI client is wired")
        }
    }

    function fullScreenSave() {
        var base = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
        var file = base + "/Screenshots/" + new Date().toISOString().replace(/[:T]/g, "-").replace(/\..*$/, "") + ".png"
        root.captureWithoutOverlay(function() { root.fullScreenCaptureRequested(file) })
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close"); }
}
