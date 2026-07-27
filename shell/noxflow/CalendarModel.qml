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
    property var events: []  // list of {date, title, time, duration, calendar, calendarColor, description, location, allDay}
    property var calendars: [] // list of {name, color, visible}

    // ── Sync state ──
    property bool syncing: false
    property bool lastSyncSuccess: false
    property string lastSyncTime: ""
    property string lastError: ""

    // ── Cache path ──
    readonly property string stateDir: {
        var s = Quickshell.env("XDG_STATE_HOME");
        if (!s) s = Quickshell.env("HOME") + "/.local/state";
        return s + "/noxflow";
    }
    readonly property string cachePath: stateDir + "/calendar.json"
    readonly property string syncScript: Quickshell.env("HOME") + "/Documents/code/dotfiles/external/waylandar-backend/sync.py"
    readonly property int syncInterval: 300000  // 5 min

    // ── FileView cache reader ──
    property FileView cacheFile: FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false
        onLoaded: {
            try {
                var json = JSON.parse(cacheFile.text());
                if (Array.isArray(json.events)) root.events = json.events;
                if (Array.isArray(json.calendars)) root.calendars = json.calendars;
                root.lastSyncTime = json.lastSync || "";
                root.lastSyncSuccess = true;
                root.lastError = "";
            } catch (e) {
                root.lastError = "Cache parse error: " + e;
            }
        }
        onLoadFailed: function(error) {
            root.lastError = "No cache yet — run sync.py --auth once";
        }
    }

    // ── Sync process ──
    property Process syncProcess: Process {
        id: syncProcess
        running: false
        onExited: function(code, status) {
            root.syncing = false;
            if (code === 0) {
                // Reload the cache file after sync completes
                root.cacheFile.path = root.cachePath;
            } else {
                root.lastError = "Sync failed (exit " + code + ")";
                root.lastSyncSuccess = false;
            }
        }
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
    }

    function goPrevMonth() {
        month--;
        if (month < 0) { month = 11; year--; }
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
        if (syncing) return;
        syncing = true;
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
