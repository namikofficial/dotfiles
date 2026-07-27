// QuickSnipSettings — reads env vars for capture configuration.
// Simpler than FileView approach — env vars are always available.

import QtQml
import Quickshell

QtObject {
    id: root

    readonly property string ocrLanguage: Quickshell.env("NOXFLOW_OCR_LANG") || "eng+fra"
    readonly property string searchEngine: Quickshell.env("NOXFLOW_SEARCH_ENGINE") || "google"
    readonly property string aiEndpoint: Quickshell.env("NOXFLOW_AI_ENDPOINT") || "http://127.0.0.1:8080/v1/chat/completions"
    readonly property string aiModel: Quickshell.env("NOXFLOW_AI_MODEL") || "qwen3-4b-local"
    readonly property int aiThreshold: parseInt(Quickshell.env("NOXFLOW_AI_THRESHOLD"), 10) || 15
    readonly property bool autoCopy: Quickshell.env("NOXFLOW_OCR_AUTOCOPY") === "1"
    readonly property bool autoSave: Quickshell.env("NOXFLOW_OCR_AUTOSAVE") === "1"
    readonly property string saveDir: Quickshell.env("NOXFLOW_SCREENSHOT_DIR") || (Quickshell.env("HOME") + "/Pictures/Screenshots")
    readonly property string lensProvider: Quickshell.env("NOXFLOW_LENS_PROVIDER") || "google"

    // Format toggles (can be overridden at runtime via toolbar buttons)
    property bool rawMode: false       // preserve raw OCR layout (no awk reformatting)
    property bool singleLine: false    // flatten to single line
    property bool directMode: false    // skip OCR, copy raw selection image

    function load() {
        // Nothing to load — all config comes from env vars
    }
}
