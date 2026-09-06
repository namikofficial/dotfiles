// CalendarModel — date/time + event store with Waylandar-style sync.
// Reads JSON cache from waylandar-backend/sync.py via FileView.
// Triggers sync via Process, manages background refresh timer.

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property string providerName: "calendar"
    property string status: "available"
    readonly property bool available: status === "available"

    // ── Current view state ──
    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()  // 0-indexed
    property int selectedDay: new Date().getDate()

    // ── Events ──
    property var events: []  // list of {id, date, title, time, duration, calendar, calendarColor, description, location, allDay}
    property var calendars: [] // list of {name, color, visible}

    // ── Sync state ──
    // syncStatus: idle | syncing | error
    property string syncStatus: "idle"
    // cacheStatus: fresh | stale | loading | error | offline
    // "fresh"   = cache loaded within 2x syncInterval
    // "stale"   = cache loaded but older than 2x syncInterval
    // "loading" = FileView currently reloading
    // "error"   = last sync attempt produced an error
    // "offline" = no cache and not syncing
    property string cacheStatus: "offline"
    property bool lastSyncSuccess: false
    property string lastSyncTime: ""       // ISO string of last attempt
    property string lastSuccessfulSyncTime: ""  // ISO string of last success
    property string lastError: ""

    // ── Last-good-data (preserved across transient failures) ──
    property var lastGoodEvents: []
    property var lastGoodCalendars: []

    // ── Cache path ──
    readonly property string stateDir: {
        var s = Quickshell.env("XDG_STATE_HOME");
        if (!s) s = Quickshell.env("HOME") + "/.local/state";
        return s + "/noxflow";
    }
    readonly property string cachePath: stateDir + "/calendar.json"
    readonly property string syncScript: Quickshell.env("HOME") + "/Documents/code/dotfiles/external/waylandar-backend/sync.py"
    readonly property int syncInterval: 300000  // 5 min
    readonly property int staleThreshold: syncInterval * 2  // 10 min

    // ── FileView cache reader ──
    // watchChanges stays false: sync.py writes the file externally so we use
    // explicit reloadCache() after sync instead of FileView's watch mechanism.
    property FileView cacheFile: FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false
        onLoaded: {
            root.cacheStatus = "loading";
            try {
                var json = JSON.parse(cacheFile.text());
                var newEvents = Array.isArray(json.events) ? json.events : [];
                var newCalendars = Array.isArray(json.calendars) ? json.calendars : [];
                var cacheErrors = Array.isArray(json.errors) ? json.errors : [];

                // A cache carrying sync errors is a failed refresh; retain the
                // last known-good data while exposing the failure to the UI.
                if (cacheErrors.length === 0) {
                    root.events = newEvents;
                    root.calendars = newCalendars;
                    root.lastGoodEvents = newEvents;
                    root.lastGoodCalendars = newCalendars;
                    root.lastSuccessfulSyncTime = json.lastSync || "";
                    root.lastError = "";
                } else {
                    root.lastError = cacheErrors.join(" / ");
                }
                root.lastSyncTime = json.lastSync || "";
                root.lastSyncSuccess = cacheErrors.length === 0;
                root.cacheStatus = cacheErrors.length === 0
                    ? computeCacheFreshness(json.lastSync) : "error";
            } catch (e) {
                root.lastError = "Cache parse error: " + e;
                root.lastSyncSuccess = false;
                root.cacheStatus = "error";
            }
        }
        onLoadFailed: function(error) {
            root.lastError = "No cache yet — run sync.py --auth once";
            root.lastSyncSuccess = false;
            root.cacheStatus = "offline";
            // Restore last good data so UI still shows something
            if (root.lastGoodEvents.length > 0) {
                root.events = root.lastGoodEvents;
                root.calendars = root.lastGoodCalendars;
            }
        }
    }

    // ── Compute cache freshness from lastSync timestamp ──
    function computeCacheFreshness(lastSyncIso) {
        if (!lastSyncIso) return "stale";
        try {
            var age = Date.now() - new Date(lastSyncIso).getTime();
            return age < root.staleThreshold ? "fresh" : "stale";
        } catch (e) {
            return "stale";
        }
    }

    // ── Sync process ──
    property Process syncProcess: Process {
        id: syncProcess
        running: false
        onExited: function(code, status) {
            root.syncing = false;
            root.syncStatus = "idle";
            if (code === 0) {
                root.lastSyncSuccess = true;
                root.lastError = "";
                root.syncStatus = "idle";
                // Force FileView to re-read the updated cache file.
                // Reassigning path triggers FileView's reload.
                root.reloadCache();
            } else {
                root.lastError = "Sync failed (exit " + code + ")";
                root.lastSyncSuccess = false;
                root.syncStatus = "error";
                root.cacheStatus = "error";
            }
        }
    }

    // Writable syncing flag (written by onExited; also mirrors syncProcess.running)
    property bool syncing: false

    // ── Force cache reload (used after sync completes) ──
    function reloadCache() {
        // Temporarily clear path to force FileView to re-evaluate,
        // then reassign to trigger a fresh load.
        cacheFile.path = "";
        cacheFile.path = root.cachePath;
    }

    // ── Background sync timer ──
    property Timer syncTimer: Timer {
        id: syncTimer
        interval: root.syncInterval
        repeat: true
        running: true
        onTriggered: root.syncGCal()
    }

    // ── Public API ──
    function today() {
        var d = new Date();
        year = d.getFullYear();
        month = d.getMonth();
        selectedDay = d.getDate();
    }

    function goNextMonth() {
        month++;
        if (month > 11) { month = 0; year++; }
        // Clamp selectedDay to valid range for the new month
        var maxDay = daysInMonth(year, month);
        if (selectedDay > maxDay) selectedDay = maxDay;
    }

    function goPrevMonth() {
        month--;
        if (month < 0) { month = 11; year--; }
        // Clamp selectedDay to valid range for the new month
        var maxDay = daysInMonth(year, month);
        if (selectedDay > maxDay) selectedDay = maxDay;
    }

    function goToMonth(y, m) {
        year = y;
        month = m;
        var maxDay = daysInMonth(year, month);
        if (selectedDay > maxDay) selectedDay = maxDay;
    }

    function daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate();
    }

    function firstDayOfMonth(y, m) {
        return new Date(y, m, 1).getDay(); // 0=Sun
    }

    function monthName(m) {
        var names = ["January","February","March","April","May","June",
                      "July","August","September","October","November","December"];
        return names[m] || "";
    }

    function eventsForDay(year, month, day) {
        var dateStr = year + "-" + String(month + 1).padStart(2, "0") + "-" + String(day).padStart(2, "0");
        var result = [];
        for (var i = 0; i < events.length; i++) {
            if (events[i].date === dateStr) result.push(events[i]);
        }
        return result;
    }

    function hasEvents(year, month, day) {
        return eventsForDay(year, month, day).length > 0;
    }

    // ── Event management (local) ──
    function addEvent(dateStr, title, time, duration, calendar, description) {
        events.push({
            date: dateStr,
            title: title || "Event",
            time: time || "",
            duration: duration || "",
            calendar: calendar || "Personal",
            calendarColor: "#4285f4",
            description: description || "",
            location: "",
            allDay: time === ""
        });
    }

    // ── Google Calendar sync (real — runs sync.py, reads cache via FileView) ──
    function syncGCal() {
        if (syncProcess.running) return;
        root.syncing = true;
        root.syncStatus = "syncing";
        root.lastError = "";
        syncProcess.command = ["python3", root.syncScript, "--cache", root.cachePath, "--look-ahead", "30"];
        syncProcess.running = true;
    }

    // ── Weekday labels ──
    readonly property var weekdayLabels: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // ── Init ──
    function start() {
        // Try loading cache. If it doesn't exist yet, sync will create it.
        cacheFile.path = root.cachePath;
        syncGCal();
    }
}
