import QtQuick
import Quickshell
import Quickshell.Io

// One place that runs an external program for the shell.
//
// Before this existed every surface hand-rolled its own `Process` with its own
// ad-hoc exit handling, so the same three mistakes were made over and over:
//
//   * the exit code was thrown away, so a failure was indistinguishable from
//     success unless the surface remembered to write its own banner
//   * stderr was swallowed (`2>/dev/null`, `|| echo`) inside the command, so
//     the UI could not say *why* something failed
//   * the command was assigned before `running` was cleared, so a second run
//     could be dropped or reuse the previous argv
//
// This runner fixes all three: it always captures stdout and stderr, always
// reports the exit code through `exited()`, and `run()` clears the previous
// argv, buffers and exit code before starting.
//
// Usage:
//
//   property Command openUrl: Command { }
//   openUrl.run(["xdg-open", url])
//   // or, for anything shell-shaped:
//   openUrl.runShell("grim -g " + rect + " " + file)
//
// Callers that need to write to stdin enable it and use the process directly:
//
//   copy.stdinEnabled = true
//   copy.run(["wl-copy"])
//   copy.process.write(text)
QtObject {
    id: root

    // Human-readable name used in error messages, e.g. "Restart daemon".
    property string label: ""

    property var command: []
    property bool running: false

    // Accumulated output. Always captured, including for commands that used to
    // redirect stderr to /dev/null, so a failure can be explained.
    property string output: ""
    property string errorOutput: ""

    // Exit code of the last finished run; -1 when nothing has run yet.
    property int lastExitCode: -1
    readonly property bool succeeded: root.lastExitCode === 0
    // True while a run is in flight. Use this, not `running`, when deciding
    // whether a button should be enabled.
    readonly property bool busy: root.running

    property bool stdinEnabled: false

    signal started()
    signal exited(int exitCode)

    // `running` is synchronised by hand in both directions. It used to be a
    // binding (`proc.running: root.running`), but a Process clears its own
    // `running` when the program exits, which broke the binding and left
    // `root.running` true forever: run() then refused every later call and
    // SystemModel polled exactly once per shell lifetime.
    onRunningChanged: {
        if (proc.running !== root.running) proc.running = root.running;
        // A start that fails without ever reporting running (bad argv,
        // missing binary) would otherwise leave this stuck at true again.
        if (root.running) Qt.callLater(function() { if (root.running && !proc.running) root.running = false; });
    }

    property Process process: Process {
        id: proc
        command: root.command
        stdinEnabled: root.stdinEnabled
        onRunningChanged: if (root.running !== proc.running) root.running = proc.running

        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.output += String(data === undefined || data === null ? "" : data) }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.errorOutput += String(data === undefined || data === null ? "" : data) }
        }

        onStarted: root.started()

        onExited: function(exitCode) {
            root.lastExitCode = exitCode;
            // Clear before notifying, so an onExited handler can start the
            // next run immediately.
            root.running = false;
            root.exited(exitCode);
        }
    }

    /// Run argv. Returns false (and does nothing) if the previous run has not
    /// finished, so callers cannot silently lose a command.
    function run(argv) {
        if (root.running) return false;
        if (!argv || argv.length === 0) return false;
        root.running = false;
        root.command = [];
        root.output = "";
        root.errorOutput = "";
        root.lastExitCode = -1;
        root.command = argv;
        root.running = true;
        return true;
    }

    /// Run a shell pipeline. Prefer run(argv): quoting here is the caller's
    /// problem, and `sh -c` makes every invocation a new shell.
    function runShell(script) {
        return run(["sh", "-c", String(script)]);
    }

    /// A one-line explanation for the UI: the exit code plus stderr when the
    /// program left any, so a failure never shows as a bare number.
    function failureText() {
        var detail = root.errorOutput.trim();
        if (detail === "") return (root.label || "Command") + " failed (exit " + root.lastExitCode + ")";
        return (root.label || "Command") + " failed (exit " + root.lastExitCode + "): " + detail;
    }
}