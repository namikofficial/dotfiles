// Apps.qml — the single registry of every outside program the shell launches.
//
// No view hardcodes an external command any more. Each entry is probed once at
// startup with a single `command -v` sweep, so a missing binary disables its
// UI entry with an explanatory tooltip instead of failing silently.
//
// Adding a program: add an entry here, then reference it by id. Never add a
// bare command string to a view.

pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import "../components" as Components

QtObject {
    id: root

    // id -> { command, label, args? }
    // `args` is prepended to the caller-supplied argument list.
    readonly property var programs: ({
        // Desktop / user-facing
        "terminal":     { command: "kitty",     label: "Terminal" },
        "files":        { command: "dolphin",   label: "File manager" },
        "browser":      { command: "firefox",   label: "Browser" },
        "editor":       { command: "code",      label: "Code editor" },
        "notes":        { command: "obsidian",  label: "Notes" },
        // Shell plumbing
        "xdgOpen":      { command: "xdg-open",  label: "Open with default app" },
        "systemctl":    { command: "systemctl",  label: "Service control" },
        "loginctl":     { command: "loginctl",  label: "Session control" },
        "hyprctl":      { command: "hyprctl",   label: "Compositor control" },
        // Capture / OCR
        "grim":         { command: "grim",      label: "Screen capture" },
        "tesseract":    { command: "tesseract", label: "Text recognition" },
        "notifySend":   { command: "notify-send", label: "Desktop notification" }
        // No dunstctl: Quickshell owns the notification bus outright, so DND is
        // NotificationModel.dnd rather than a command to probe for.
    })

    // id -> true when the binary resolved at startup.
    property var availability: ({})

    // True once the probe finished (successfully or not).
    readonly property bool probed: probeDone

    // Set when the probe itself could not run.
    property string probeError: ""

    property bool probeDone: false

    // ── Public API ──

    /// True when the program is registered and its binary was found.
    function isAvailable(id) {
        return availability[id] === true;
    }

    /// Human-readable explanation for a disabled entry. Empty when available.
    function unavailableReason(id) {
        if (!programs[id]) return "Unknown program: " + id;
        if (isAvailable(id)) return "";
        return programs[id].label + " is unavailable: " + programs[id].command + " is not installed";
    }

    /// Full command line for logging and tests. Empty for unknown ids.
    function commandLine(id, args) {
        var entry = programs[id];
        if (!entry) return "";
        var parts = [entry.command];
        if (entry.args) parts = parts.concat(entry.args);
        if (args && args.length) parts = parts.concat(args);
        return parts.join(" ");
    }

    /// Launch a registered program detached.
    /// Returns { ok: bool, reason: string } so callers can surface a failure
    /// instead of dropping it.
    function invoke(id, args) {
        if (!programs[id])
            return { ok: false, reason: "Unknown program: " + id };
        if (!isAvailable(id))
            return { ok: false, reason: unavailableReason(id) };
        var argv = [];
        if (programs[id].args) argv = argv.concat(programs[id].args);
        if (args && args.length) argv = argv.concat(args);
        argv.unshift(programs[id].command);
        try {
            Quickshell.execDetached(argv);
        } catch (error) {
            return { ok: false, reason: programs[id].label + " failed to start: " + error };
        }
        return { ok: true, reason: "" };
    }

    // ── Startup probe ──
    // One `sh` invocation emits "<id>=<resolved>" for every id whose binary is
    // on PATH. A single fork keeps startup cost flat as the table grows.
    function probe() {
        var ids = [];
        for (var id in programs) ids.push(id);
        if (ids.length === 0) { probeDone = true; return; }

        var script = "";
        for (var i = 0; i < ids.length; i++) {
            var key = ids[i];
            if (i > 0) script += "; ";
            script += "if command -v " + programs[key].command + " >/dev/null 2>&1; then printf '%s=1\\n' " + key + "; fi";
        }

        probeError = "";
        probeProcess.run(["sh", "-c", script]);
    }

    property Components.Command probeProcess: Components.Command {
        label: "Program availability probe"
        onExited: function(exitCode) {
            var found = {};
            var lines = root.probeProcess.output.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim();
                if (line === "") continue;
                var eq = line.indexOf("=");
                if (eq < 0) continue;
                if (root.programs[line.slice(0, eq)]) found[line.slice(0, eq)] = true;
            }
            root.availability = found;
            if (exitCode !== 0)
                root.probeError = root.probeProcess.failureText();
            root.probeDone = true;

            var missing = [];
            for (var id in root.programs)
                if (!found[id]) missing.push(root.programs[id].command);
            if (missing.length > 0)
                console.warn("apps: unavailable programs disabled:", missing.join(", "));
            else
                console.info("apps: all registered programs available");
        }
    }

    Component.onCompleted: probe()
}