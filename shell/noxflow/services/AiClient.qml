// AiClient.qml — the shell's single AI path.
//
// Launcher ("Ask AI") and Capture (analyze recognised text) both use this
// client. There is no `ai_query` daemon action: noxd rejects it.
//
// Configuration comes from noxd settings — `ai.endpoint`, `ai.model`,
// `ai.provider` — so the shell and the daemon can never disagree about which
// model is in use. Env vars are only the boot-time default before the daemon
// answers, never a silent override once settings are known.

import QtQml
import QtQuick

QtObject {
    id: root

    /// The NoxdClient. Assigned by shell.qml.
    property var noxd: null

    // ── Configuration ──
    // Defaults exist so the client is usable before noxd subscribes. They are
    // overwritten by the daemon's settings as soon as getSettings returns.
    property string endpoint: "http://127.0.0.1:8080/v1/chat/completions"
    property string model: "qwen3-4b-local"
    property string provider: "openai-compatible"

    property bool configuredFromDaemon: false

    readonly property int timeoutMs: 30000

    // ── Request state ──
    // status: 0 idle | 1 loading | 2 ok | 3 error
    property int status: 0
    property string response: ""
    property string errorDetail: ""
    property bool loading: false
    property string lastQuery: ""

    // Bumped on every new request and on reset so a late XHR callback for a
    // superseded query can never overwrite current state.
    property int generation: 0

    property var xhr: null
    property bool settingsInFlight: false

    // QtObject has no default property, so the timers are declared as typed
    // properties rather than as child objects.
    property Timer debounce: Timer {
        interval: 350
        repeat: false
        onTriggered: root.send(root.pendingQuery)
    }
    property string pendingQuery: ""

    property Timer timeout: Timer {
        interval: root.timeoutMs
        repeat: false
        onTriggered: {
            if (root.xhr) { try { root.xhr.abort() } catch (e) {} root.xhr = null }
            root.loading = false;
            root.status = 3;
            root.response = "AI timed out after " + (root.timeoutMs / 1000) + "s";
            root.errorDetail = "Endpoint: " + root.endpoint;
        }
    }

    function reset() {
        generation++;
        pendingQuery = "";
        debounce.stop();
        timeout.stop();
        if (xhr) { try { xhr.abort() } catch (e) {} xhr = null }
        loading = false;
        status = 0;
        response = "";
        errorDetail = "";
        lastQuery = "";
    }

    /// Read the AI configuration from noxd settings. Safe to call repeatedly;
    /// an in-flight read is not duplicated.
    function refreshSettings() {
        if (!noxd || !noxd.connected || settingsInFlight) return false;
        settingsInFlight = true;
        noxd.getSettings(function(result) {
            root.settingsInFlight = false;
            var data = result && result.data && result.data.settings;
            if (!data) return;
            if (data["ai.endpoint"] !== undefined && String(data["ai.endpoint"]) !== "")
                endpoint = String(data["ai.endpoint"]);
            if (data["ai.model"] !== undefined && String(data["ai.model"]) !== "")
                model = String(data["ai.model"]);
            if (data["ai.provider"] !== undefined && String(data["ai.provider"]) !== "")
                provider = String(data["ai.provider"]);
            configuredFromDaemon = true;
        }, function() {
            root.settingsInFlight = false;
        });
        return true;
    }

    /// Queue a query with a debounce, for live search-as-you-type surfaces.
    function query(text) {
        var trimmed = String(text || "").trim();
        if (trimmed.length < 3) {
            if (status !== 0) reset();
            return;
        }
        pendingQuery = trimmed;
        debounce.restart();
    }

    /// Send immediately, for surfaces with an explicit submit action.
    function ask(prompt, systemPrompt) {
        pendingQuery = String(prompt || "").trim();
        debounce.stop();
        send(pendingQuery, systemPrompt);
    }

    function send(query, systemPrompt) {
        var trimmed = String(query || "").trim();
        if (trimmed === "") { reset(); return false }
        if (endpoint === "") {
            loading = false;
            status = 3;
            response = "AI is not configured";
            errorDetail = "Set ai.endpoint in noxd settings (setup/check-shell.sh can show it)";
            return false;
        }

        var gen = ++generation;
        loading = true;
        status = 1;
        response = "";
        errorDetail = "";
        lastQuery = trimmed;

        var request = new XMLHttpRequest();
        xhr = request;
        request.open("POST", endpoint, true);
        request.setRequestHeader("Content-Type", "application/json");
        request.timeout = timeoutMs;
        request.ontimeout = function() {
            if (gen !== generation) return;
            xhr = null;
            loading = false;
            status = 3;
            response = "AI timed out after " + (timeoutMs / 1000) + "s";
            errorDetail = "Endpoint: " + endpoint;
        };
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return;
            if (gen !== generation) return;
            timeout.stop();
            xhr = null;
            loading = false;
            if (request.status === 200) {
                try {
                    var parsed = JSON.parse(request.responseText);
                    response = parsed.choices[0].message.content || "No response";
                    status = 2;
                } catch (e) {
                    response = "Failed to parse the AI response";
                    errorDetail = String(e);
                    status = 3;
                }
            } else if (request.status === 0) {
                response = "AI endpoint unreachable";
                errorDetail = "Nothing answered at " + endpoint;
                status = 3;
            } else {
                response = "AI request failed (HTTP " + request.status + ")";
                errorDetail = endpoint;
                status = 3;
            }
        };
        timeout.start();
        request.send(JSON.stringify({
            model: model,
            messages: [
                { role: "system", content: systemPrompt || "You are a helpful assistant. Answer concisely." },
                { role: "user", content: trimmed }
            ],
            temperature: 0.7,
            max_tokens: 512,
            stream: false
        }));
        return true;
    }
}